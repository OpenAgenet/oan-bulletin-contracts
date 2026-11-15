// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { BulletinStateMachine, C } = require('../lib/governance');

const metas = ['meta1', 'meta2', 'meta3', 'meta4'];
const admins = ['admin1', 'admin2', 'admin3', 'admin4'];
const baseProposal = (overrides = {}) => ({
  committeeType: C.COMMITTEE_ADMIN,
  actionType: C.ACTION_REGISTRAR_AUTHORIZE,
  targetAddress: 'registrar-account',
  targetDid: 'did:oan:registrar:one',
  subjectType: C.SUBJECT_REGISTRAR,
  authorizedDomains: ['example.com'],
  policyHash: 'policy', metadataHash: 'metadata', paramsHash: 'params',
  effectiveFromMs: 0, subjectExpiryMs: 0, thresholdValue: 0,
  ...overrides,
});

test('admin votes authorize and then suspend a registrar', () => {
  const state = BulletinStateMachine.initialize('did:oan:root', metas, admins, 3);
  const id = BulletinStateMachine.createProposal(state, baseProposal(), 'admin1', 1000);
  for (const actor of admins.slice(0, 3)) BulletinStateMachine.vote(state, id, true, actor, 1000);
  const event = BulletinStateMachine.refreshProposalStatus(state, id, 1000);
  assert.equal(event.sequence, 1);
  assert.deepEqual(BulletinStateMachine.subjectSnapshot(state, C.SUBJECT_REGISTRAR, 'did:oan:registrar:one', 1000), {
    exists: true, authorized: true, status: C.SUBJECT_ACTIVE, version: 1, effectiveFromMs: 0, expiresAtMs: 0,
  });

  const updateId = BulletinStateMachine.createProposal(state, baseProposal({ actionType: C.ACTION_REGISTRAR_DOMAINS_UPDATE, authorizedDomains: ['api.example.com', 'example.com'], policyHash: 'policy-2' }), 'admin1', 1001);
  for (const actor of admins.slice(0, 3)) BulletinStateMachine.vote(state, updateId, true, actor, 1001);
  BulletinStateMachine.refreshProposalStatus(state, updateId, 1001);
  assert.deepEqual(state.subjects['1:did:oan:registrar:one'].authorizedDomains, ['api.example.com', 'example.com']);
  assert.equal(state.subjects['1:did:oan:registrar:one'].version, 2);

  const suspendId = BulletinStateMachine.createProposal(state, baseProposal({ actionType: C.ACTION_REGISTRAR_SUSPEND, authorizedDomains: [] }), 'admin1', 1002);
  for (const actor of admins.slice(0, 3)) BulletinStateMachine.vote(state, suspendId, true, actor, 1002);
  BulletinStateMachine.refreshProposalStatus(state, suspendId, 1002);
  const snapshot = BulletinStateMachine.subjectSnapshot(state, C.SUBJECT_REGISTRAR, 'did:oan:registrar:one', 1002);
  assert.equal(snapshot.status, C.SUBJECT_SUSPENDED);
  assert.equal(snapshot.authorized, false);
  assert.equal(snapshot.version, 3);
});

test('stale approved proposals are rejected instead of mutating invalid state', () => {
  const state = BulletinStateMachine.initialize('did:oan:root', metas, admins, 3);
  const first = BulletinStateMachine.createProposal(state, baseProposal(), 'admin1', 2000);
  const stale = BulletinStateMachine.createProposal(state, baseProposal(), 'admin2', 2000);
  for (const actor of admins.slice(0, 3)) {
    BulletinStateMachine.vote(state, first, true, actor, 2000);
    BulletinStateMachine.vote(state, stale, true, actor, 2000);
  }
  BulletinStateMachine.refreshProposalStatus(state, first, 2000);
  BulletinStateMachine.refreshProposalStatus(state, stale, 2000);
  assert.equal(state.proposals.find((p) => p.proposalId === stale).status, C.PROPOSAL_REJECTED);
});

test('canonical domain validation rejects uppercase and unsorted domains', () => {
  const state = BulletinStateMachine.initialize('did:oan:root', metas, admins, 3);
  assert.throws(() => BulletinStateMachine.createProposal(state, baseProposal({ authorizedDomains: ['Example.com'] }), 'admin1', 3000), /canonical/);
  assert.throws(() => BulletinStateMachine.createProposal(state, baseProposal({ authorizedDomains: ['z.example', 'a.example'] }), 'admin1', 3000), /unsorted/);
});

test('lowering the admin threshold does not change an existing proposal snapshot', () => {
  const state = BulletinStateMachine.initialize('did:oan:root', metas, admins, 3);
  const subjectProposal = BulletinStateMachine.createProposal(state, baseProposal(), 'admin1', 4000);
  const thresholdProposal = BulletinStateMachine.createProposal(state, baseProposal({
    committeeType: C.COMMITTEE_META_ADMIN,
    actionType: C.ACTION_ADMIN_THRESHOLD_UPDATE,
    targetAddress: '', targetDid: '', subjectType: C.SUBJECT_NONE,
    authorizedDomains: [], thresholdValue: 1,
  }), 'meta1', 4000);
  for (const actor of metas.slice(0, 3)) BulletinStateMachine.vote(state, thresholdProposal, true, actor, 4000);
  BulletinStateMachine.refreshProposalStatus(state, thresholdProposal, 4000);
  assert.equal(state.adminThreshold, 1);

  BulletinStateMachine.vote(state, subjectProposal, true, 'admin1', 4000);
  BulletinStateMachine.refreshProposalStatus(state, subjectProposal, 4000);
  assert.equal(state.proposals.find((p) => p.proposalId === subjectProposal).status, C.PROPOSAL_PENDING);
  assert.equal(state.proposals.find((p) => p.proposalId === subjectProposal).requiredApprovals, 3);
});

test('root DID rotation uses the meta committee and preserves the previous root in the event', () => {
  const state = BulletinStateMachine.initialize('did:oan:root', metas, admins, 3);
  const id = BulletinStateMachine.createProposal(state, baseProposal({
    committeeType: C.COMMITTEE_META_ADMIN,
    actionType: C.ACTION_ROOT_DID_ROTATE,
    targetAddress: '', targetDid: 'did:oan:root:next', subjectType: C.SUBJECT_NONE,
    authorizedDomains: [],
  }), 'meta1', 5000);
  for (const actor of metas.slice(0, 3)) BulletinStateMachine.vote(state, id, true, actor, 5000);
  const event = BulletinStateMachine.refreshProposalStatus(state, id, 5000);
  assert.equal(state.rootAuthorityDid, 'did:oan:root:next');
  assert.equal(event.rootAuthorityDid, 'did:oan:root');
  assert.equal(event.subjectDid, 'did:oan:root:next');
});

test('proposal expires only after the voting window', () => {
  const state = BulletinStateMachine.initialize('did:oan:root', metas, admins, 3);
  const id = BulletinStateMachine.createProposal(state, baseProposal(), 'admin1', 6000);
  BulletinStateMachine.refreshProposalStatus(state, id, 6000 + C.MAX_VOTING_WINDOW_MS + 1);
  assert.equal(state.proposals.find((p) => p.proposalId === id).status, C.PROPOSAL_EXPIRED);
});
