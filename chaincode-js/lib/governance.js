// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

'use strict';

const crypto = require('node:crypto');

const C = Object.freeze({
  MEMBER_ACTIVE: 1, MEMBER_DISABLED: 2, MEMBER_REMOVED: 3,
  SUBJECT_NONE: 0, SUBJECT_REGISTRAR: 1, SUBJECT_DISCOVERY: 2, SUBJECT_VC_ISSUER: 3,
  SUBJECT_ACTIVE: 1, SUBJECT_SUSPENDED: 2, SUBJECT_REVOKED: 3,
  COMMITTEE_META_ADMIN: 1, COMMITTEE_ADMIN: 2,
  ACTION_META_ADD: 1, ACTION_META_DISABLE: 2, ACTION_META_ENABLE: 3, ACTION_META_REMOVE: 4,
  ACTION_ADMIN_ADD: 11, ACTION_ADMIN_DISABLE: 12, ACTION_ADMIN_ENABLE: 13, ACTION_ADMIN_REMOVE: 14,
  ACTION_ADMIN_THRESHOLD_UPDATE: 15,
  ACTION_REGISTRAR_AUTHORIZE: 21, ACTION_REGISTRAR_SUSPEND: 22, ACTION_REGISTRAR_RECOVER: 23,
  ACTION_REGISTRAR_REVOKE: 24, ACTION_REGISTRAR_DOMAINS_UPDATE: 25,
  ACTION_DISCOVERY_AUTHORIZE: 31, ACTION_DISCOVERY_DOMAINS_UPDATE: 32,
  ACTION_DISCOVERY_SUSPEND: 33, ACTION_DISCOVERY_RECOVER: 34, ACTION_DISCOVERY_REVOKE: 35,
  ACTION_VC_ISSUER_AUTHORIZE: 41, ACTION_VC_ISSUER_SUSPEND: 42,
  ACTION_VC_ISSUER_RECOVER: 43, ACTION_VC_ISSUER_REVOKE: 44,
  ACTION_ROOT_DID_ROTATE: 51,
  PROPOSAL_PENDING: 1, PROPOSAL_PASSED: 2, PROPOSAL_EXPIRED: 3, PROPOSAL_REJECTED: 4,
  MIN_ACTIVE_META_ADMINS: 4, MIN_ACTIVE_ADMINS: 4,
  MAX_CONFIGURED_META_ADMINS: 15, MAX_CONFIGURED_ADMINS: 25,
  MAX_VOTING_WINDOW_MS: 864000000, MAX_PENDING_PROPOSALS: 256, MAX_TOTAL_PROPOSALS: 300,
  MAX_DID_BYTES: 256, MAX_DOMAIN_COUNT: 116, MAX_DOMAIN_BYTES: 128, MAX_HASH_BYTES: 256,
  MAX_ROOT_AUTHORITY_DID_BYTES: 128,
});

const utf8Length = (value) => Buffer.byteLength(value || '', 'utf8');
const copy = (value) => JSON.parse(JSON.stringify(value));
const subjectKey = (type, did) => `${type}:${did}`;

class BulletinStateMachine {
  static initialize(rootAuthorityDid, metaAdmins, admins, adminThreshold) {
    this.#require(utf8Length(rootAuthorityDid) > 0, 'empty root DID');
    this.#require(utf8Length(rootAuthorityDid) <= C.MAX_ROOT_AUTHORITY_DID_BYTES, 'root DID too large');
    this.#require(Array.isArray(metaAdmins) && metaAdmins.length >= C.MIN_ACTIVE_META_ADMINS, 'too few meta admins');
    this.#require(Array.isArray(admins) && admins.length >= C.MIN_ACTIVE_ADMINS, 'too few admins');
    this.#require(metaAdmins.length <= C.MAX_CONFIGURED_META_ADMINS, 'too many meta admins');
    this.#require(admins.length <= C.MAX_CONFIGURED_ADMINS, 'too many admins');
    this.#validateUniqueMembers(metaAdmins);
    this.#validateUniqueMembers(admins);
    const threshold = this.#safeUInt(Number(adminThreshold), 'invalid threshold');
    this.#validateAdminThreshold(threshold, admins.length);
    return {
      rootAuthorityDid,
      metaAdmins: metaAdmins.map((id) => ({ id, status: C.MEMBER_ACTIVE })),
      admins: admins.map((id) => ({ id, status: C.MEMBER_ACTIVE })),
      adminThreshold: threshold,
      nextProposalId: 1,
      nextEventSequence: 0,
      proposals: [],
      subjects: {},
      lastEventDigest: '',
      lastClockMs: 0,
    };
  }

  static createProposal(state, input, actor, nowMs) {
    this.#touchClock(state, nowMs);
    const committeeType = Number(input.committeeType);
    const actionType = Number(input.actionType);
    const subjectType = Number(input.subjectType);
    this.#require(committeeType === this.#expectedCommittee(actionType), 'invalid committee');
    this.#assertActiveMember(state, committeeType, actor);
    this.#validateActionSubject(actionType, subjectType);
    const normalized = {
      committeeType, actionType, subjectType,
      targetAddress: String(input.targetAddress || ''),
      targetDid: String(input.targetDid || ''),
      authorizedDomains: Array.isArray(input.authorizedDomains) ? input.authorizedDomains.map(String) : [],
      policyHash: String(input.policyHash || ''),
      metadataHash: String(input.metadataHash || ''),
      paramsHash: String(input.paramsHash || ''),
      effectiveFromMs: this.#safeUInt(Number(input.effectiveFromMs || 0), 'invalid effective time'),
      subjectExpiryMs: this.#safeUInt(Number(input.subjectExpiryMs || 0), 'invalid expiry'),
      thresholdValue: this.#safeUInt(Number(input.thresholdValue || 0), 'invalid threshold'),
    };
    if (actionType === C.ACTION_ROOT_DID_ROTATE) {
      this.#require(normalized.targetAddress === '', 'invalid root DID target');
      this.#require(normalized.targetDid !== state.rootAuthorityDid, 'root DID unchanged');
    }
    this.#validateProposalInput(normalized, nowMs);
    this.#pruneFinalized(state);
    this.#require(state.proposals.filter((p) => p.status === C.PROPOSAL_PENDING).length < C.MAX_PENDING_PROPOSALS, 'too many pending proposals');
    if (actionType === C.ACTION_ADMIN_THRESHOLD_UPDATE) this.#validateAdminThreshold(normalized.thresholdValue, this.#countActive(state.admins));
    const proposal = {
      proposalId: state.nextProposalId++, ...normalized, createdBy: actor,
      createdAtMs: nowMs, expiresAtMs: nowMs + C.MAX_VOTING_WINDOW_MS,
      requiredApprovals: committeeType === C.COMMITTEE_META_ADMIN ? this.#maxThreshold(this.#countActive(state.metaAdmins)) : state.adminThreshold,
      status: C.PROPOSAL_PENDING, approvals: 0, rejections: 0,
      approvalVoters: [], rejectionVoters: [], finalizedAtMs: 0,
    };
    state.proposals.push(proposal);
    return proposal.proposalId;
  }

  static vote(state, proposalId, approve, actor, nowMs) {
    this.#touchClock(state, nowMs);
    const proposal = this.#proposal(state, proposalId);
    this.#assertActiveMember(state, proposal.committeeType, actor);
    this.#require(proposal.status === C.PROPOSAL_PENDING, 'proposal not pending');
    this.#require(nowMs <= proposal.expiresAtMs, 'proposal expired');
    this.#require(!proposal.approvalVoters.includes(actor) && !proposal.rejectionVoters.includes(actor), 'duplicate vote');
    if (approve) { proposal.approvalVoters.push(actor); proposal.approvals++; }
    else { proposal.rejectionVoters.push(actor); proposal.rejections++; }
  }

  static refreshProposalStatus(state, proposalId, nowMs) {
    this.#touchClock(state, nowMs);
    const proposal = this.#proposal(state, proposalId);
    this.#require(proposal.status === C.PROPOSAL_PENDING, 'proposal not pending');
    if (proposal.approvals >= proposal.requiredApprovals) {
      proposal.finalizedAtMs = nowMs;
      if (!this.#canApply(state, proposal)) { proposal.status = C.PROPOSAL_REJECTED; return null; }
      proposal.status = C.PROPOSAL_PASSED;
      return this.#apply(state, proposal, nowMs);
    }
    if (nowMs > proposal.expiresAtMs) {
      proposal.status = C.PROPOSAL_EXPIRED;
      proposal.finalizedAtMs = nowMs;
    }
    return null;
  }

  static subjectSnapshot(state, subjectType, did, atMs) {
    this.#safeUInt(Number(atMs), 'invalid snapshot time');
    const subject = state.subjects[subjectKey(Number(subjectType), did)];
    if (!subject) return { exists: false, authorized: false, status: C.SUBJECT_NONE, version: 0, effectiveFromMs: 0, expiresAtMs: 0 };
    return {
      exists: true,
      authorized: subject.status === C.SUBJECT_ACTIVE && (!subject.effectiveFromMs || subject.effectiveFromMs <= atMs) && (!subject.expiresAtMs || atMs < subject.expiresAtMs),
      status: subject.status, version: subject.version,
      effectiveFromMs: subject.effectiveFromMs, expiresAtMs: subject.expiresAtMs,
    };
  }

  static #validateProposalInput(input, nowMs) {
    this.#require(input.metadataHash.length > 0 && input.paramsHash.length > 0, 'required hash empty');
    for (const hash of [input.policyHash, input.metadataHash, input.paramsHash]) this.#require(utf8Length(hash) <= C.MAX_HASH_BYTES, 'hash too large');
    if (input.subjectType === C.SUBJECT_NONE) {
      if (input.actionType === C.ACTION_ROOT_DID_ROTATE) this.#require(utf8Length(input.targetDid) > 0 && utf8Length(input.targetDid) <= C.MAX_ROOT_AUTHORITY_DID_BYTES, 'invalid root DID');
      else this.#require(input.targetDid === '', 'unexpected DID');
      this.#require(input.authorizedDomains.length === 0, 'unexpected domains');
      return;
    }
    this.#require(utf8Length(input.targetDid) > 0 && utf8Length(input.targetDid) <= C.MAX_DID_BYTES, 'invalid subject DID');
    this.#require(!input.effectiveFromMs || input.effectiveFromMs <= nowMs, 'invalid effective time');
    this.#require(!input.subjectExpiryMs || input.subjectExpiryMs > nowMs, 'invalid expiry');
    this.#require(!input.subjectExpiryMs || input.effectiveFromMs <= input.subjectExpiryMs, 'invalid timing');
    if (this.#isDomainsAction(input.actionType)) this.#validateDomains(input.authorizedDomains);
    else this.#require(input.authorizedDomains.length === 0, 'unexpected domains');
  }

  static #validateDomains(domains) {
    this.#require(domains.length > 0 && domains.length <= C.MAX_DOMAIN_COUNT, 'invalid domain count');
    domains.forEach((domain, index) => {
      this.#require(utf8Length(domain) > 0 && utf8Length(domain) <= C.MAX_DOMAIN_BYTES, 'invalid domain length');
      this.#require(!/[A-Z]/.test(domain), 'domain not canonical');
      if (domain === '*') this.#require(domains.length === 1, 'wildcard mixed');
      if (index > 0) this.#require(Buffer.compare(Buffer.from(domains[index - 1]), Buffer.from(domain)) < 0, 'domains unsorted');
    });
  }

  static #validateActionSubject(action, subject) {
    if (this.#isMemberAction(action) || action === C.ACTION_ADMIN_THRESHOLD_UPDATE || action === C.ACTION_ROOT_DID_ROTATE) this.#require(subject === C.SUBJECT_NONE, 'invalid subject type');
    else if (action >= 21 && action <= 25) this.#require(subject === C.SUBJECT_REGISTRAR, 'invalid subject type');
    else if (action >= 31 && action <= 35) this.#require(subject === C.SUBJECT_DISCOVERY, 'invalid subject type');
    else if (action >= 41 && action <= 44) this.#require(subject === C.SUBJECT_VC_ISSUER, 'invalid subject type');
    else throw new Error('invalid action');
  }

  static #expectedCommittee(action) {
    if (this.#isMemberAction(action) || action === C.ACTION_ADMIN_THRESHOLD_UPDATE || action === C.ACTION_ROOT_DID_ROTATE) return C.COMMITTEE_META_ADMIN;
    if ((action >= 21 && action <= 25) || (action >= 31 && action <= 35) || (action >= 41 && action <= 44)) return C.COMMITTEE_ADMIN;
    throw new Error('invalid action');
  }

  static #canApply(state, p) {
    if (p.actionType === C.ACTION_META_ADD) return !this.#findMember(state.metaAdmins, p.targetAddress) && this.#countConfigured(state.metaAdmins) < C.MAX_CONFIGURED_META_ADMINS;
    if ([C.ACTION_META_DISABLE, C.ACTION_META_REMOVE].includes(p.actionType)) return this.#canDeactivate(state.metaAdmins, p.targetAddress, C.MIN_ACTIVE_META_ADMINS);
    if (p.actionType === C.ACTION_META_ENABLE) return this.#hasStatus(state.metaAdmins, p.targetAddress, C.MEMBER_DISABLED);
    if (p.actionType === C.ACTION_ADMIN_ADD) return !this.#findMember(state.admins, p.targetAddress) && this.#countConfigured(state.admins) < C.MAX_CONFIGURED_ADMINS;
    if ([C.ACTION_ADMIN_DISABLE, C.ACTION_ADMIN_REMOVE].includes(p.actionType)) return this.#canDeactivate(state.admins, p.targetAddress, C.MIN_ACTIVE_ADMINS);
    if (p.actionType === C.ACTION_ADMIN_ENABLE) return this.#hasStatus(state.admins, p.targetAddress, C.MEMBER_DISABLED);
    if (p.actionType === C.ACTION_ADMIN_THRESHOLD_UPDATE) return p.thresholdValue >= 1 && p.thresholdValue <= this.#maxThreshold(this.#countActive(state.admins));
    if (p.actionType === C.ACTION_ROOT_DID_ROTATE) return p.targetDid !== state.rootAuthorityDid;
    const subject = state.subjects[subjectKey(p.subjectType, p.targetDid)];
    if (this.#isAuthorize(p.actionType)) return !subject;
    if (this.#isDomainsUpdate(p.actionType) || this.#isSuspend(p.actionType)) return subject?.status === C.SUBJECT_ACTIVE;
    if (this.#isRecover(p.actionType)) return subject?.status === C.SUBJECT_SUSPENDED;
    if (this.#isRevoke(p.actionType)) return subject && [C.SUBJECT_ACTIVE, C.SUBJECT_SUSPENDED].includes(subject.status);
    return false;
  }

  static #apply(state, p, nowMs) {
    if (p.actionType === C.ACTION_META_ADD) state.metaAdmins.push({ id: p.targetAddress, status: C.MEMBER_ACTIVE });
    else if (p.actionType === C.ACTION_META_DISABLE) this.#deactivate(state.metaAdmins, p.targetAddress, C.MEMBER_DISABLED);
    else if (p.actionType === C.ACTION_META_ENABLE) this.#enable(state.metaAdmins, p.targetAddress);
    else if (p.actionType === C.ACTION_META_REMOVE) this.#deactivate(state.metaAdmins, p.targetAddress, C.MEMBER_REMOVED);
    else if (p.actionType === C.ACTION_ADMIN_ADD) state.admins.push({ id: p.targetAddress, status: C.MEMBER_ACTIVE });
    else if (p.actionType === C.ACTION_ADMIN_DISABLE) this.#deactivate(state.admins, p.targetAddress, C.MEMBER_DISABLED);
    else if (p.actionType === C.ACTION_ADMIN_ENABLE) this.#enable(state.admins, p.targetAddress);
    else if (p.actionType === C.ACTION_ADMIN_REMOVE) this.#deactivate(state.admins, p.targetAddress, C.MEMBER_REMOVED);
    else if (p.actionType === C.ACTION_ADMIN_THRESHOLD_UPDATE) state.adminThreshold = p.thresholdValue;
    else if (p.actionType === C.ACTION_ROOT_DID_ROTATE) {
      const previousRoot = state.rootAuthorityDid;
      state.rootAuthorityDid = p.targetDid;
      return this.#executionEvent(state, p, nowMs, previousRoot, null);
    } else this.#applySubject(state, p, nowMs);
    const subject = p.subjectType === C.SUBJECT_NONE ? null : state.subjects[subjectKey(p.subjectType, p.targetDid)];
    return this.#executionEvent(state, p, nowMs, state.rootAuthorityDid, subject);
  }

  static #applySubject(state, p, nowMs) {
    const key = subjectKey(p.subjectType, p.targetDid);
    let subject = state.subjects[key];
    if (this.#isAuthorize(p.actionType)) {
      state.subjects[key] = { subjectDid: p.targetDid, subjectType: p.subjectType, status: C.SUBJECT_ACTIVE, authorizedDomains: copy(p.authorizedDomains), policyHash: p.policyHash, metadataHash: p.metadataHash, effectiveFromMs: p.effectiveFromMs, expiresAtMs: p.subjectExpiryMs, version: 1, updatedAtMs: nowMs };
      return;
    }
    if (this.#isDomainsUpdate(p.actionType)) subject.authorizedDomains = copy(p.authorizedDomains);
    else if (this.#isSuspend(p.actionType)) subject.status = C.SUBJECT_SUSPENDED;
    else if (this.#isRecover(p.actionType)) subject.status = C.SUBJECT_ACTIVE;
    else if (this.#isRevoke(p.actionType)) subject.status = C.SUBJECT_REVOKED;
    subject.policyHash = p.policyHash;
    subject.metadataHash = p.metadataHash;
    subject.version++;
    subject.updatedAtMs = nowMs;
  }

  static #executionEvent(state, p, nowMs, eventRootDid, subject) {
    const event = {
      eventType: p.actionType, sequence: ++state.nextEventSequence, rootAuthorityDid: eventRootDid,
      proposalId: p.proposalId, committeeType: p.committeeType, targetAddress: p.targetAddress,
      subjectDid: p.targetDid, subjectType: p.subjectType, subjectStatus: subject?.status || C.SUBJECT_NONE,
      authorizedDomains: copy(subject?.authorizedDomains || []), effectiveFromMs: subject?.effectiveFromMs || 0,
      expiresAtMs: subject?.expiresAtMs || 0, policyHash: subject?.policyHash || p.policyHash,
      metadataHash: subject?.metadataHash || p.metadataHash, previousEventDigest: state.lastEventDigest,
      emittedAtMs: nowMs,
    };
    event.eventDigest = crypto.createHash('sha3-256').update(JSON.stringify(event)).digest('hex');
    state.lastEventDigest = event.eventDigest;
    return event;
  }

  static #proposal(state, id) { const p = state.proposals.find((item) => item.proposalId === Number(id)); this.#require(p, 'proposal not found'); return p; }
  static #findMember(members, id) { return members.find((member) => member.id === id); }
  static #hasStatus(members, id, status) { return this.#findMember(members, id)?.status === status; }
  static #canDeactivate(members, id, minimum) { return this.#hasStatus(members, id, C.MEMBER_ACTIVE) && this.#countActive(members) > minimum; }
  static #deactivate(members, id, status) { this.#findMember(members, id).status = status; }
  static #enable(members, id) { this.#findMember(members, id).status = C.MEMBER_ACTIVE; }
  static #countActive(members) { return members.filter((m) => m.status === C.MEMBER_ACTIVE).length; }
  static #countConfigured(members) { return members.filter((m) => m.status !== C.MEMBER_REMOVED).length; }
  static #maxThreshold(active) { return Math.floor(active * 2 / 3) + 1; }
  static #validateAdminThreshold(threshold, active) { this.#require(Number.isSafeInteger(threshold) && threshold >= 1 && threshold <= this.#maxThreshold(active), 'invalid threshold'); }
  static #safeUInt(value, message) { this.#require(Number.isSafeInteger(value) && value >= 0, message); return value; }
  static #validateUniqueMembers(members) { this.#require(members.every((id) => typeof id === 'string' && id.length > 0), 'empty member'); this.#require(new Set(members).size === members.length, 'duplicate member'); }
  static #assertActiveMember(state, committee, actor) { const members = committee === C.COMMITTEE_META_ADMIN ? state.metaAdmins : committee === C.COMMITTEE_ADMIN ? state.admins : null; this.#require(members, 'invalid committee'); this.#require(this.#hasStatus(members, actor, C.MEMBER_ACTIVE), 'not active member'); }
  static #touchClock(state, nowMs) { this.#require(Number.isSafeInteger(nowMs) && nowMs >= state.lastClockMs, 'clock regression'); state.lastClockMs = nowMs; }
  static #pruneFinalized(state) { while (state.proposals.length >= C.MAX_TOTAL_PROPOSALS) { const index = state.proposals.findIndex((p) => p.status !== C.PROPOSAL_PENDING); if (index < 0) return; state.proposals.splice(index, 1); } }
  static #isMemberAction(a) { return (a >= 1 && a <= 4) || (a >= 11 && a <= 14); }
  static #isDomainsAction(a) { return [21, 25, 31, 32].includes(a); }
  static #isAuthorize(a) { return [21, 31, 41].includes(a); }
  static #isDomainsUpdate(a) { return [25, 32].includes(a); }
  static #isSuspend(a) { return [22, 33, 42].includes(a); }
  static #isRecover(a) { return [23, 34, 43].includes(a); }
  static #isRevoke(a) { return [24, 35, 44].includes(a); }
  static #require(condition, message) { if (!condition) throw new Error(message); }
}

module.exports = { BulletinStateMachine, C };
