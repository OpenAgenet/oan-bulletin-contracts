// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

'use strict';

const { Contract } = require('fabric-contract-api');
const { BulletinStateMachine } = require('./governance');

const STATE_KEY = 'OAN_BULLETIN';

class OanBulletinContract extends Contract {
  async Initialize(ctx, rootAuthorityDid, metaAdminsJson, adminsJson, adminThreshold) {
    const existing = await ctx.stub.getState(STATE_KEY);
    if (existing?.length) throw new Error('bulletin already initialized');
    const state = BulletinStateMachine.initialize(rootAuthorityDid, JSON.parse(metaAdminsJson), JSON.parse(adminsJson), Number(adminThreshold));
    await this.#write(ctx, state);
    ctx.stub.setEvent('BulletinInitialized', Buffer.from(JSON.stringify({
      rootAuthorityDid,
      metaAdmins: JSON.parse(metaAdminsJson),
      admins: JSON.parse(adminsJson),
      adminThreshold: Number(adminThreshold),
      publisher: ctx.clientIdentity.getID(),
    }), 'utf8'));
    return JSON.stringify(state);
  }

  async CreateProposal(ctx, proposalJson) {
    const state = await this.#read(ctx);
    const id = BulletinStateMachine.createProposal(state, JSON.parse(proposalJson), ctx.clientIdentity.getID(), this.#timestampMs(ctx));
    await this.#write(ctx, state);
    return String(id);
  }

  async Vote(ctx, proposalId, approve) {
    const state = await this.#read(ctx);
    BulletinStateMachine.vote(state, Number(proposalId), approve === true || approve === 'true', ctx.clientIdentity.getID(), this.#timestampMs(ctx));
    await this.#write(ctx, state);
  }

  async RefreshProposalStatus(ctx, proposalId) {
    const state = await this.#read(ctx);
    const event = BulletinStateMachine.refreshProposalStatus(state, Number(proposalId), this.#timestampMs(ctx));
    await this.#write(ctx, state);
    if (event) ctx.stub.setEvent('GovernanceExecution', Buffer.from(JSON.stringify(event), 'utf8'));
    return JSON.stringify(state.proposals.find((proposal) => proposal.proposalId === Number(proposalId)));
  }

  async GetBulletin(ctx) { return JSON.stringify(await this.#read(ctx)); }

  async GetProposal(ctx, proposalId) {
    const state = await this.#read(ctx);
    const proposal = state.proposals.find((item) => item.proposalId === Number(proposalId));
    if (!proposal) throw new Error('proposal not found');
    return JSON.stringify(proposal);
  }

  async GetProposalStatus(ctx, proposalId) {
    return String(JSON.parse(await this.GetProposal(ctx, proposalId)).status);
  }

  async GetMemberStatus(ctx, committeeType, identity) {
    const state = await this.#read(ctx);
    const type = Number(committeeType);
    const members = type === 1 ? state.metaAdmins : type === 2 ? state.admins : null;
    if (!members) throw new Error('invalid committee');
    const member = members.find((item) => item.id === identity);
    if (!member) throw new Error('member not found');
    return String(member.status);
  }

  async GetSubject(ctx, subjectType, subjectDid) {
    const state = await this.#read(ctx);
    return JSON.stringify(state.subjects[`${Number(subjectType)}:${subjectDid}`] || null);
  }

  async GetSubjectStatus(ctx, subjectType, subjectDid) {
    const subject = JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid));
    return String(subject ? subject.status : 0);
  }

  async GetSubjectVersion(ctx, subjectType, subjectDid) {
    const subject = JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid));
    return String(subject ? subject.version : 0);
  }

  async GetSubjectDomainCount(ctx, subjectType, subjectDid) {
    const subject = JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid));
    return String(subject ? subject.authorizedDomains.length : 0);
  }

  async SubjectExists(ctx, subjectType, subjectDid) {
    return String(JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid)) !== null);
  }

  async GetSubjectDid(ctx, subjectType, subjectDid) {
    const subject = JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid));
    return subject ? subject.subjectDid : '';
  }

  async GetSubjectPolicyHash(ctx, subjectType, subjectDid) {
    const subject = JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid));
    return subject ? subject.policyHash : '';
  }

  async GetSubjectMetadataHash(ctx, subjectType, subjectDid) {
    const subject = JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid));
    return subject ? subject.metadataHash : '';
  }

  async GetSubjectAuthorizedDomains(ctx, subjectType, subjectDid) {
    const subject = JSON.parse(await this.GetSubject(ctx, subjectType, subjectDid));
    return JSON.stringify(subject ? subject.authorizedDomains : []);
  }

  async GetSubjectAuthorizationAt(ctx, subjectType, subjectDid, atMs) {
    const state = await this.#read(ctx);
    return JSON.stringify(BulletinStateMachine.subjectSnapshot(state, Number(subjectType), subjectDid, Number(atMs)));
  }

  async RegistrarIsAuthorizedAt(ctx, subjectDid, atMs) {
    return String(JSON.parse(await this.GetSubjectAuthorizationAt(ctx, 1, subjectDid, atMs)).authorized);
  }

  async DiscoveryIsAuthorizedAt(ctx, subjectDid, atMs) {
    return String(JSON.parse(await this.GetSubjectAuthorizationAt(ctx, 2, subjectDid, atMs)).authorized);
  }

  async VcIssuerIsAuthorizedAt(ctx, subjectDid, atMs) {
    return String(JSON.parse(await this.GetSubjectAuthorizationAt(ctx, 3, subjectDid, atMs)).authorized);
  }

  async #read(ctx) {
    const data = await ctx.stub.getState(STATE_KEY);
    if (!data?.length) throw new Error('bulletin not initialized');
    return JSON.parse(data.toString('utf8'));
  }

  async #write(ctx, state) { await ctx.stub.putState(STATE_KEY, Buffer.from(JSON.stringify(state), 'utf8')); }

  #timestampMs(ctx) {
    const timestamp = ctx.stub.getTxTimestamp();
    const seconds = typeof timestamp.seconds === 'object' ? Number(timestamp.seconds.toString()) : Number(timestamp.seconds);
    return seconds * 1000 + Math.floor(Number(timestamp.nanos || 0) / 1_000_000);
  }
}

module.exports = { OanBulletinContract };
