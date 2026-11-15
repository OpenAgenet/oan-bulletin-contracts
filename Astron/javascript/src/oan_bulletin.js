// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

"use strict";

let STATE_KEY = "oan:bulletin:state";
let PROPOSAL_PREFIX = "oan:bulletin:proposal:";
let SUBJECT_PREFIX = "oan:bulletin:subject:";
let EVENT_PREFIX = "oan:bulletin:event:";
let MAX_SAFE_INTEGER = 9007199254740991;

let MEMBER_ACTIVE = 1;
let MEMBER_DISABLED = 2;
let MEMBER_REMOVED = 3;
let SUBJECT_NONE = 0;
let SUBJECT_REGISTRAR = 1;
let SUBJECT_DISCOVERY = 2;
let SUBJECT_VC_ISSUER = 3;
let SUBJECT_ACTIVE = 1;
let SUBJECT_SUSPENDED = 2;
let SUBJECT_REVOKED = 3;
let COMMITTEE_META_ADMIN = 1;
let COMMITTEE_ADMIN = 2;
let ACTION_META_ADD = 1;
let ACTION_META_DISABLE = 2;
let ACTION_META_ENABLE = 3;
let ACTION_META_REMOVE = 4;
let ACTION_ADMIN_ADD = 11;
let ACTION_ADMIN_DISABLE = 12;
let ACTION_ADMIN_ENABLE = 13;
let ACTION_ADMIN_REMOVE = 14;
let ACTION_ADMIN_THRESHOLD_UPDATE = 15;
let ACTION_REGISTRAR_AUTHORIZE = 21;
let ACTION_REGISTRAR_SUSPEND = 22;
let ACTION_REGISTRAR_RECOVER = 23;
let ACTION_REGISTRAR_REVOKE = 24;
let ACTION_REGISTRAR_DOMAINS_UPDATE = 25;
let ACTION_DISCOVERY_AUTHORIZE = 31;
let ACTION_DISCOVERY_DOMAINS_UPDATE = 32;
let ACTION_DISCOVERY_SUSPEND = 33;
let ACTION_DISCOVERY_RECOVER = 34;
let ACTION_DISCOVERY_REVOKE = 35;
let ACTION_VC_ISSUER_AUTHORIZE = 41;
let ACTION_VC_ISSUER_SUSPEND = 42;
let ACTION_VC_ISSUER_RECOVER = 43;
let ACTION_VC_ISSUER_REVOKE = 44;
let ACTION_ROOT_DID_ROTATE = 51;
let PROPOSAL_PENDING = 1;
let PROPOSAL_PASSED = 2;
let PROPOSAL_EXPIRED = 3;
let PROPOSAL_REJECTED = 4;

let MIN_ACTIVE_META_ADMINS = 4;
let MIN_ACTIVE_ADMINS = 4;
let MAX_CONFIGURED_META_ADMINS = 15;
let MAX_CONFIGURED_ADMINS = 25;
let MAX_VOTING_WINDOW_MS = 864000000;
let MAX_PENDING_PROPOSALS = 256;
let MAX_TOTAL_PROPOSALS = 300;
let MAX_DID_BYTES = 256;
let MAX_DOMAIN_COUNT = 116;
let MAX_DOMAIN_BYTES = 128;
let MAX_HASH_BYTES = 256;
let MAX_ROOT_AUTHORITY_DID_BYTES = 128;

function requireThat(condition, message) {
    Utils.assert(condition, message);
}

function safeUInt(value, message) {
    requireThat(typeof value === "number" && value >= 0 && value <= MAX_SAFE_INTEGER && value % 1 === 0, message);
    return value;
}

function normalizeTimestampMs(value) {
    let timestamp = safeUInt(Number(value), "invalid block timestamp");
    if (timestamp < 100000000000) { return timestamp * 1000; }
    if (timestamp >= 100000000000000) { return parseInt(timestamp / 1000, 10); }
    return timestamp;
}

function utf8Length(value) {
    let length = 0;
    let i = 0;
    let code = 0;
    while (i < value.length) {
        code = value.charCodeAt(i);
        if (code < 128) { length += 1; }
        else if (code < 2048) { length += 2; }
        else if (code >= 55296 && code <= 56319 && i + 1 < value.length) { length += 4; i += 1; }
        else { length += 3; }
        i += 1;
    }
    return length;
}

function utf8Bytes(value) {
    let result = [];
    let i = 0;
    let code = 0;
    let next = 0;
    while (i < value.length) {
        code = value.charCodeAt(i);
        if (code >= 55296 && code <= 56319 && i + 1 < value.length) {
            next = value.charCodeAt(i + 1);
            if (next >= 56320 && next <= 57343) { code = 65536 + (code - 55296) * 1024 + next - 56320; i += 1; }
        }
        if (code < 128) { result.push(code); }
        else if (code < 2048) { result.push(192 | code >> 6); result.push(128 | code & 63); }
        else if (code < 65536) { result.push(224 | code >> 12); result.push(128 | code >> 6 & 63); result.push(128 | code & 63); }
        else { result.push(240 | code >> 18); result.push(128 | code >> 12 & 63); result.push(128 | code >> 6 & 63); result.push(128 | code & 63); }
        i += 1;
    }
    return result;
}

function compareUtf8(left, right) {
    let leftBytes = utf8Bytes(left);
    let rightBytes = utf8Bytes(right);
    let length = leftBytes.length < rightBytes.length ? leftBytes.length : rightBytes.length;
    let i = 0;
    while (i < length) {
        if (leftBytes[i] < rightBytes[i]) { return -1; }
        if (leftBytes[i] > rightBytes[i]) { return 1; }
        i += 1;
    }
    if (leftBytes.length < rightBytes.length) { return -1; }
    if (leftBytes.length > rightBytes.length) { return 1; }
    return 0;
}

function loadJson(key) {
    let value = Chain.load(key);
    if (value === false || value === "") { return null; }
    return JSON.parse(value);
}

function storeJson(key, value) {
    Chain.store(key, JSON.stringify(value));
}

function loadState() {
    let state = loadJson(STATE_KEY);
    requireThat(state !== null, "bulletin not initialized");
    return state;
}

function proposalKey(id) { return PROPOSAL_PREFIX + String(id); }
function loadProposal(id) { let proposal = loadJson(proposalKey(id)); requireThat(proposal !== null, "proposal not found"); return proposal; }
function storeProposal(proposal) { storeJson(proposalKey(proposal.proposalId), proposal); }
function subjectKey(type, did) { return SUBJECT_PREFIX + Utils.sha256(String(type) + ":" + did, 1); }
function loadSubject(type, did) { return loadJson(subjectKey(type, did)); }
function storeSubject(subject) { storeJson(subjectKey(subject.subjectType, subject.subjectDid), subject); }

function findMember(members, address) {
    let i = 0;
    while (i < members.length) {
        if (members[i].address === address) { return i; }
        i += 1;
    }
    return -1;
}

function countActive(members) {
    let count = 0;
    let i = 0;
    while (i < members.length) { if (members[i].status === MEMBER_ACTIVE) { count += 1; } i += 1; }
    return count;
}

function countConfigured(members) {
    let count = 0;
    let i = 0;
    while (i < members.length) { if (members[i].status !== MEMBER_REMOVED) { count += 1; } i += 1; }
    return count;
}

function maxThreshold(active) { return parseInt(active * 2 / 3, 10) + 1; }

function validateAdminThreshold(threshold, active) {
    requireThat(threshold >= 1 && threshold <= maxThreshold(active), "invalid threshold");
}

function assertActiveMember(state, committee, address) {
    let members = committee === COMMITTEE_META_ADMIN ? state.metaAdmins : committee === COMMITTEE_ADMIN ? state.admins : null;
    requireThat(members !== null, "invalid committee");
    let index = findMember(members, address);
    requireThat(index >= 0 && members[index].status === MEMBER_ACTIVE, "not active member");
}

function isMemberAction(action) { return (action >= 1 && action <= 4) || (action >= 11 && action <= 14); }
function isAuthorize(action) { return action === ACTION_REGISTRAR_AUTHORIZE || action === ACTION_DISCOVERY_AUTHORIZE || action === ACTION_VC_ISSUER_AUTHORIZE; }
function isDomainsUpdate(action) { return action === ACTION_REGISTRAR_DOMAINS_UPDATE || action === ACTION_DISCOVERY_DOMAINS_UPDATE; }
function isDomainsAction(action) { return isAuthorize(action) && action !== ACTION_VC_ISSUER_AUTHORIZE || isDomainsUpdate(action); }
function isSuspend(action) { return action === ACTION_REGISTRAR_SUSPEND || action === ACTION_DISCOVERY_SUSPEND || action === ACTION_VC_ISSUER_SUSPEND; }
function isRecover(action) { return action === ACTION_REGISTRAR_RECOVER || action === ACTION_DISCOVERY_RECOVER || action === ACTION_VC_ISSUER_RECOVER; }
function isRevoke(action) { return action === ACTION_REGISTRAR_REVOKE || action === ACTION_DISCOVERY_REVOKE || action === ACTION_VC_ISSUER_REVOKE; }

function expectedCommittee(action) {
    if (isMemberAction(action) || action === ACTION_ADMIN_THRESHOLD_UPDATE || action === ACTION_ROOT_DID_ROTATE) { return COMMITTEE_META_ADMIN; }
    if ((action >= 21 && action <= 25) || (action >= 31 && action <= 35) || (action >= 41 && action <= 44)) { return COMMITTEE_ADMIN; }
    throw "invalid action";
}

function validateActionSubject(action, subjectType) {
    if (isMemberAction(action) || action === ACTION_ADMIN_THRESHOLD_UPDATE || action === ACTION_ROOT_DID_ROTATE) { requireThat(subjectType === SUBJECT_NONE, "invalid subject type"); }
    else if (action >= 21 && action <= 25) { requireThat(subjectType === SUBJECT_REGISTRAR, "invalid subject type"); }
    else if (action >= 31 && action <= 35) { requireThat(subjectType === SUBJECT_DISCOVERY, "invalid subject type"); }
    else if (action >= 41 && action <= 44) { requireThat(subjectType === SUBJECT_VC_ISSUER, "invalid subject type"); }
    else { throw "invalid action"; }
}

function validateDomains(domains) {
    requireThat(domains.length > 0 && domains.length <= MAX_DOMAIN_COUNT, "invalid domain count");
    let i = 0;
    let j = 0;
    let code = 0;
    while (i < domains.length) {
        requireThat(utf8Length(domains[i]) > 0 && utf8Length(domains[i]) <= MAX_DOMAIN_BYTES, "invalid domain length");
        j = 0;
        while (j < domains[i].length) { code = domains[i].charCodeAt(j); requireThat(code < 65 || code > 90, "domain not canonical"); j += 1; }
        if (domains[i] === "*") { requireThat(domains.length === 1, "wildcard mixed"); }
        if (i > 0) { requireThat(compareUtf8(domains[i - 1], domains[i]) < 0, "domains unsorted"); }
        i += 1;
    }
}

function validateProposalInput(input, nowMs) {
    requireThat(input.metadataHash.length > 0 && input.paramsHash.length > 0, "required hash empty");
    requireThat(utf8Length(input.policyHash) <= MAX_HASH_BYTES && utf8Length(input.metadataHash) <= MAX_HASH_BYTES && utf8Length(input.paramsHash) <= MAX_HASH_BYTES, "hash too large");
    if (input.subjectType === SUBJECT_NONE) {
        if (input.actionType === ACTION_ROOT_DID_ROTATE) { requireThat(utf8Length(input.targetDid) > 0 && utf8Length(input.targetDid) <= MAX_ROOT_AUTHORITY_DID_BYTES, "invalid root DID"); }
        else { requireThat(input.targetDid === "", "unexpected DID"); }
        requireThat(input.authorizedDomains.length === 0, "unexpected domains");
        return;
    }
    requireThat(utf8Length(input.targetDid) > 0 && utf8Length(input.targetDid) <= MAX_DID_BYTES, "invalid subject DID");
    requireThat(input.effectiveFromMs === 0 || input.effectiveFromMs <= nowMs, "invalid effective time");
    requireThat(input.subjectExpiryMs === 0 || input.subjectExpiryMs > nowMs, "invalid expiry");
    requireThat(input.subjectExpiryMs === 0 || input.effectiveFromMs <= input.subjectExpiryMs, "invalid timing");
    if (isDomainsAction(input.actionType)) { validateDomains(input.authorizedDomains); }
    else { requireThat(input.authorizedDomains.length === 0, "unexpected domains"); }
}

function touchClock(state, nowMs) { requireThat(nowMs >= state.lastClockMs, "clock regression"); state.lastClockMs = nowMs; }

function pruneFinalized(state) {
    let i = 0;
    let proposal = null;
    while (state.proposalIds.length >= MAX_TOTAL_PROPOSALS) {
        i = 0;
        while (i < state.proposalIds.length) {
            proposal = loadProposal(state.proposalIds[i]);
            if (proposal.status !== PROPOSAL_PENDING) { Chain.del(proposalKey(proposal.proposalId)); state.proposalIds.splice(i, 1); break; }
            i += 1;
        }
        if (i === state.proposalIds.length) { return; }
    }
}

function createProposal(state, params, nowMs) {
    let action = Number(params.actionType);
    let committee = Number(params.committeeType);
    let subjectType = Number(params.subjectType);
    requireThat(committee === expectedCommittee(action), "invalid committee");
    assertActiveMember(state, committee, Chain.msg.sender);
    validateActionSubject(action, subjectType);
    let input = {
        committeeType: committee, actionType: action, subjectType: subjectType,
        targetAddress: String(params.targetAddress || ""), targetDid: String(params.targetDid || ""),
        authorizedDomains: params.authorizedDomains || [], policyHash: String(params.policyHash || ""),
        metadataHash: String(params.metadataHash || ""), paramsHash: String(params.paramsHash || ""),
        effectiveFromMs: safeUInt(Number(params.effectiveFromMs || 0), "invalid effective time"),
        subjectExpiryMs: safeUInt(Number(params.subjectExpiryMs || 0), "invalid expiry"),
        thresholdValue: safeUInt(Number(params.thresholdValue || 0), "invalid threshold")
    };
    if (input.targetAddress !== "") { requireThat(Utils.addressCheck(input.targetAddress), "invalid target address"); }
    if (action === ACTION_ROOT_DID_ROTATE) { requireThat(input.targetAddress === "", "invalid root DID target"); requireThat(input.targetDid !== state.rootAuthorityDid, "root DID unchanged"); }
    validateProposalInput(input, nowMs);
    pruneFinalized(state);
    requireThat(state.pendingProposalCount < MAX_PENDING_PROPOSALS, "too many pending proposals");
    if (action === ACTION_ADMIN_THRESHOLD_UPDATE) { validateAdminThreshold(input.thresholdValue, countActive(state.admins)); }
    let proposal = input;
    proposal.proposalId = state.nextProposalId;
    state.nextProposalId += 1;
    proposal.createdBy = Chain.msg.sender;
    proposal.createdAtMs = nowMs;
    proposal.expiresAtMs = nowMs + MAX_VOTING_WINDOW_MS;
    proposal.requiredApprovals = committee === COMMITTEE_META_ADMIN ? maxThreshold(countActive(state.metaAdmins)) : state.adminThreshold;
    proposal.status = PROPOSAL_PENDING;
    proposal.approvals = 0;
    proposal.rejections = 0;
    proposal.approvalVoters = [];
    proposal.rejectionVoters = [];
    proposal.finalizedAtMs = 0;
    state.proposalIds.push(proposal.proposalId);
    state.pendingProposalCount += 1;
    storeProposal(proposal);
    return proposal.proposalId;
}

function vote(state, params, nowMs) {
    let proposal = loadProposal(Number(params.proposalId));
    assertActiveMember(state, proposal.committeeType, Chain.msg.sender);
    requireThat(proposal.status === PROPOSAL_PENDING, "proposal not pending");
    requireThat(nowMs <= proposal.expiresAtMs, "proposal expired");
    requireThat(proposal.approvalVoters.indexOf(Chain.msg.sender) < 0 && proposal.rejectionVoters.indexOf(Chain.msg.sender) < 0, "duplicate vote");
    if (params.approve === true) { proposal.approvalVoters.push(Chain.msg.sender); proposal.approvals += 1; }
    else { proposal.rejectionVoters.push(Chain.msg.sender); proposal.rejections += 1; }
    storeProposal(proposal);
}

function hasStatus(members, address, status) { let index = findMember(members, address); return index >= 0 && members[index].status === status; }
function canDeactivate(members, address, minimum) { return hasStatus(members, address, MEMBER_ACTIVE) && countActive(members) > minimum; }

function canApply(state, proposal) {
    if (proposal.actionType === ACTION_META_ADD) { return findMember(state.metaAdmins, proposal.targetAddress) < 0 && countConfigured(state.metaAdmins) < MAX_CONFIGURED_META_ADMINS; }
    if (proposal.actionType === ACTION_META_DISABLE || proposal.actionType === ACTION_META_REMOVE) { return canDeactivate(state.metaAdmins, proposal.targetAddress, MIN_ACTIVE_META_ADMINS); }
    if (proposal.actionType === ACTION_META_ENABLE) { return hasStatus(state.metaAdmins, proposal.targetAddress, MEMBER_DISABLED); }
    if (proposal.actionType === ACTION_ADMIN_ADD) { return findMember(state.admins, proposal.targetAddress) < 0 && countConfigured(state.admins) < MAX_CONFIGURED_ADMINS; }
    if (proposal.actionType === ACTION_ADMIN_DISABLE || proposal.actionType === ACTION_ADMIN_REMOVE) { return canDeactivate(state.admins, proposal.targetAddress, MIN_ACTIVE_ADMINS); }
    if (proposal.actionType === ACTION_ADMIN_ENABLE) { return hasStatus(state.admins, proposal.targetAddress, MEMBER_DISABLED); }
    if (proposal.actionType === ACTION_ADMIN_THRESHOLD_UPDATE) { return proposal.thresholdValue >= 1 && proposal.thresholdValue <= maxThreshold(countActive(state.admins)); }
    if (proposal.actionType === ACTION_ROOT_DID_ROTATE) { return proposal.targetDid !== state.rootAuthorityDid; }
    let subject = loadSubject(proposal.subjectType, proposal.targetDid);
    if (isAuthorize(proposal.actionType)) { return subject === null; }
    if (isDomainsUpdate(proposal.actionType) || isSuspend(proposal.actionType)) { return subject !== null && subject.status === SUBJECT_ACTIVE; }
    if (isRecover(proposal.actionType)) { return subject !== null && subject.status === SUBJECT_SUSPENDED; }
    if (isRevoke(proposal.actionType)) { return subject !== null && (subject.status === SUBJECT_ACTIVE || subject.status === SUBJECT_SUSPENDED); }
    return false;
}

function updateMember(members, address, nextStatus) { let index = findMember(members, address); requireThat(index >= 0, "member not found"); members[index].status = nextStatus; }

function applySubject(proposal, nowMs) {
    let subject = loadSubject(proposal.subjectType, proposal.targetDid);
    if (isAuthorize(proposal.actionType)) {
        subject = { subjectDid: proposal.targetDid, subjectType: proposal.subjectType, status: SUBJECT_ACTIVE, authorizedDomains: proposal.authorizedDomains, policyHash: proposal.policyHash, metadataHash: proposal.metadataHash, effectiveFromMs: proposal.effectiveFromMs, expiresAtMs: proposal.subjectExpiryMs, version: 1, updatedAtMs: nowMs };
    } else {
        if (isDomainsUpdate(proposal.actionType)) { subject.authorizedDomains = proposal.authorizedDomains; }
        else if (isSuspend(proposal.actionType)) { subject.status = SUBJECT_SUSPENDED; }
        else if (isRecover(proposal.actionType)) { subject.status = SUBJECT_ACTIVE; }
        else if (isRevoke(proposal.actionType)) { subject.status = SUBJECT_REVOKED; }
        subject.policyHash = proposal.policyHash;
        subject.metadataHash = proposal.metadataHash;
        subject.version += 1;
        subject.updatedAtMs = nowMs;
    }
    storeSubject(subject);
    return subject;
}

function emitExecution(state, proposal, nowMs, eventRootDid, subject) {
    let event = {
        eventType: proposal.actionType, sequence: state.nextEventSequence + 1, rootAuthorityDid: eventRootDid,
        proposalId: proposal.proposalId, committeeType: proposal.committeeType, targetAddress: proposal.targetAddress,
        subjectDid: proposal.targetDid, subjectType: proposal.subjectType,
        subjectStatus: subject === null ? SUBJECT_NONE : subject.status,
        authorizedDomains: subject === null ? [] : subject.authorizedDomains,
        effectiveFromMs: subject === null ? 0 : subject.effectiveFromMs,
        expiresAtMs: subject === null ? 0 : subject.expiresAtMs,
        policyHash: subject === null ? proposal.policyHash : subject.policyHash,
        metadataHash: subject === null ? proposal.metadataHash : subject.metadataHash,
        previousEventDigest: state.lastEventDigest, emittedAtMs: nowMs
    };
    event.eventDigest = Utils.sha256(JSON.stringify(event), 1);
    state.nextEventSequence = event.sequence;
    state.lastEventDigest = event.eventDigest;
    storeJson(EVENT_PREFIX + String(event.sequence), event);
    Chain.tlog("GovernanceExecution", String(event.sequence), String(event.eventType), String(event.proposalId), event.eventDigest);
}

function applyProposal(state, proposal, nowMs) {
    let subject = null;
    if (proposal.actionType === ACTION_META_ADD) { state.metaAdmins.push({ address: proposal.targetAddress, status: MEMBER_ACTIVE }); }
    else if (proposal.actionType === ACTION_META_DISABLE) { updateMember(state.metaAdmins, proposal.targetAddress, MEMBER_DISABLED); }
    else if (proposal.actionType === ACTION_META_ENABLE) { updateMember(state.metaAdmins, proposal.targetAddress, MEMBER_ACTIVE); }
    else if (proposal.actionType === ACTION_META_REMOVE) { updateMember(state.metaAdmins, proposal.targetAddress, MEMBER_REMOVED); }
    else if (proposal.actionType === ACTION_ADMIN_ADD) { state.admins.push({ address: proposal.targetAddress, status: MEMBER_ACTIVE }); }
    else if (proposal.actionType === ACTION_ADMIN_DISABLE) { updateMember(state.admins, proposal.targetAddress, MEMBER_DISABLED); }
    else if (proposal.actionType === ACTION_ADMIN_ENABLE) { updateMember(state.admins, proposal.targetAddress, MEMBER_ACTIVE); }
    else if (proposal.actionType === ACTION_ADMIN_REMOVE) { updateMember(state.admins, proposal.targetAddress, MEMBER_REMOVED); }
    else if (proposal.actionType === ACTION_ADMIN_THRESHOLD_UPDATE) { state.adminThreshold = proposal.thresholdValue; }
    else if (proposal.actionType === ACTION_ROOT_DID_ROTATE) { let previous = state.rootAuthorityDid; state.rootAuthorityDid = proposal.targetDid; emitExecution(state, proposal, nowMs, previous, null); return; }
    else { subject = applySubject(proposal, nowMs); }
    emitExecution(state, proposal, nowMs, state.rootAuthorityDid, subject);
}

function refresh(state, params, nowMs) {
    let proposal = loadProposal(Number(params.proposalId));
    requireThat(proposal.status === PROPOSAL_PENDING, "proposal not pending");
    if (proposal.approvals >= proposal.requiredApprovals) {
        proposal.finalizedAtMs = nowMs;
        state.pendingProposalCount -= 1;
        if (!canApply(state, proposal)) { proposal.status = PROPOSAL_REJECTED; storeProposal(proposal); return; }
        proposal.status = PROPOSAL_PASSED;
        applyProposal(state, proposal, nowMs);
        storeProposal(proposal);
    } else if (nowMs > proposal.expiresAtMs) {
        proposal.status = PROPOSAL_EXPIRED;
        proposal.finalizedAtMs = nowMs;
        state.pendingProposalCount -= 1;
        storeProposal(proposal);
    }
}

function init(input) {
    requireThat(Chain.load(STATE_KEY) === false || Chain.load(STATE_KEY) === "", "already initialized");
    let params = JSON.parse(input);
    requireThat(utf8Length(params.rootAuthorityDid) > 0 && utf8Length(params.rootAuthorityDid) <= MAX_ROOT_AUTHORITY_DID_BYTES, "invalid root DID");
    requireThat(params.metaAdmins.length >= MIN_ACTIVE_META_ADMINS && params.metaAdmins.length <= MAX_CONFIGURED_META_ADMINS, "invalid meta admins");
    requireThat(params.admins.length >= MIN_ACTIVE_ADMINS && params.admins.length <= MAX_CONFIGURED_ADMINS, "invalid admins");
    let metaAdmins = [];
    let admins = [];
    let seen = {};
    let i = 0;
    while (i < params.metaAdmins.length) { requireThat(Utils.addressCheck(params.metaAdmins[i]), "invalid member address"); requireThat(!seen[params.metaAdmins[i]], "duplicate member"); seen[params.metaAdmins[i]] = true; metaAdmins.push({ address: params.metaAdmins[i], status: MEMBER_ACTIVE }); i += 1; }
    seen = {};
    i = 0;
    while (i < params.admins.length) { requireThat(Utils.addressCheck(params.admins[i]), "invalid member address"); requireThat(!seen[params.admins[i]], "duplicate member"); seen[params.admins[i]] = true; admins.push({ address: params.admins[i], status: MEMBER_ACTIVE }); i += 1; }
    let threshold = safeUInt(Number(params.adminThreshold), "invalid threshold");
    validateAdminThreshold(threshold, admins.length);
    storeJson(STATE_KEY, { rootAuthorityDid: params.rootAuthorityDid, metaAdmins: metaAdmins, admins: admins, adminThreshold: threshold, nextProposalId: 1, nextEventSequence: 0, proposalIds: [], pendingProposalCount: 0, lastEventDigest: "", lastClockMs: 0 });
    Chain.tlog("BulletinInitialized", params.rootAuthorityDid, JSON.stringify(params.metaAdmins), JSON.stringify(params.admins), String(threshold), Chain.msg.sender);
}

function main(input) {
    let request = JSON.parse(input);
    let state = loadState();
    let nowMs = normalizeTimestampMs(Chain.block.timestamp);
    touchClock(state, nowMs);
    let result = null;
    if (request.method === "createProposal") { result = createProposal(state, request.params, nowMs); }
    else if (request.method === "vote") { vote(state, request.params, nowMs); }
    else if (request.method === "refreshProposalStatus") { refresh(state, request.params, nowMs); }
    else { throw "invalid method"; }
    storeJson(STATE_KEY, state);
    return result === null ? "" : String(result);
}

function query(input) {
    let request = JSON.parse(input);
    if (request.method === "getBulletin") { return JSON.stringify(loadState()); }
    if (request.method === "getProposal") { return JSON.stringify(loadProposal(Number(request.params.proposalId))); }
    if (request.method === "getProposalStatus") { return String(loadProposal(Number(request.params.proposalId)).status); }
    if (request.method === "getSubject") { return JSON.stringify(loadSubject(Number(request.params.subjectType), request.params.subjectDid)); }
    if (request.method === "getSubjectStatus") { let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid); return String(subject === null ? SUBJECT_NONE : subject.status); }
    if (request.method === "getSubjectVersion") { let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid); return String(subject === null ? 0 : subject.version); }
    if (request.method === "getSubjectDomainCount") { let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid); return String(subject === null ? 0 : subject.authorizedDomains.length); }
    if (request.method === "subjectExists") { return String(loadSubject(Number(request.params.subjectType), request.params.subjectDid) !== null); }
    if (request.method === "getSubjectDid") { let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid); return JSON.stringify(subject === null ? "" : subject.subjectDid); }
    if (request.method === "getSubjectPolicyHash") { let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid); return JSON.stringify(subject === null ? "" : subject.policyHash); }
    if (request.method === "getSubjectMetadataHash") { let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid); return JSON.stringify(subject === null ? "" : subject.metadataHash); }
    if (request.method === "getSubjectAuthorizedDomains") { let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid); return JSON.stringify(subject === null ? [] : subject.authorizedDomains); }
    if (request.method === "getExecutionEvent") { return JSON.stringify(loadJson(EVENT_PREFIX + String(Number(request.params.sequence)))); }
    if (request.method === "getMemberStatus") {
        let state = loadState();
        let committee = Number(request.params.committeeType);
        let members = committee === COMMITTEE_META_ADMIN ? state.metaAdmins : committee === COMMITTEE_ADMIN ? state.admins : null;
        requireThat(members !== null, "invalid committee");
        let index = findMember(members, request.params.address);
        requireThat(index >= 0, "member not found");
        return String(members[index].status);
    }
    if (request.method === "getSubjectAuthorizationAt") {
        let subject = loadSubject(Number(request.params.subjectType), request.params.subjectDid);
        let atMs = Number(request.params.atMs);
        let authorized = subject !== null && subject.status === SUBJECT_ACTIVE && (subject.effectiveFromMs === 0 || subject.effectiveFromMs <= atMs) && (subject.expiresAtMs === 0 || atMs < subject.expiresAtMs);
        return JSON.stringify({ exists: subject !== null, authorized: authorized, status: subject === null ? SUBJECT_NONE : subject.status, version: subject === null ? 0 : subject.version, effectiveFromMs: subject === null ? 0 : subject.effectiveFromMs, expiresAtMs: subject === null ? 0 : subject.expiresAtMs });
    }
    throw "invalid query method";
}
