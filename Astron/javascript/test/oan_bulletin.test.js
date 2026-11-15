// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function harness() {
  const storage = new Map();
  const logs = [];
  const Chain = {
    block: { timestamp: 1_700_000_000_000 }, msg: { sender: 'meta1' },
    load: (key) => storage.has(key) ? storage.get(key) : false,
    store: (key, value) => { storage.set(key, value); return true; },
    del: (key) => storage.delete(key),
    tlog: (...args) => { logs.push(args); return true; },
  };
  const Utils = {
    assert: (condition, message) => { if (!condition) throw new Error(message); return true; },
    sha256: (data) => crypto.createHash('sha256').update(data).digest('hex'),
    addressCheck: (value) => typeof value === 'string' && value.length > 0,
  };
  const context = vm.createContext({ Chain, Utils, JSON, Number, String, parseInt });
  const source = fs.readFileSync(path.join(__dirname, '..', 'src', 'oan_bulletin.js'), 'utf8');
  vm.runInContext(source, context);
  const invoke = (sender, method, params, timestamp = Chain.block.timestamp) => {
    Chain.msg.sender = sender; Chain.block.timestamp = timestamp;
    return context.main(JSON.stringify({ method, params }));
  };
  const query = (method, params = {}) => JSON.parse(context.query(JSON.stringify({ method, params })));
  context.init(JSON.stringify({ rootAuthorityDid: 'did:oan:root', metaAdmins: ['meta1', 'meta2', 'meta3', 'meta4'], admins: ['admin1', 'admin2', 'admin3', 'admin4'], adminThreshold: 3 }));
  return { invoke, query, logs };
}

const registrarProposal = (overrides = {}) => ({
  committeeType: 2, actionType: 21, targetAddress: 'did:bid:registrar',
  targetDid: 'did:oan:registrar:one', subjectType: 1,
  authorizedDomains: ['example.com'], policyHash: 'policy', metadataHash: 'metadata', paramsHash: 'params',
  effectiveFromMs: 0, subjectExpiryMs: 0, thresholdValue: 0, ...overrides,
});

test('admin committee authorizes a registrar and emits a chained event', () => {
  const { invoke, query, logs } = harness();
  const id = invoke('admin1', 'createProposal', registrarProposal());
  for (const admin of ['admin1', 'admin2', 'admin3']) invoke(admin, 'vote', { proposalId: Number(id), approve: true });
  invoke('admin4', 'refreshProposalStatus', { proposalId: Number(id) });
  const subject = query('getSubject', { subjectType: 1, subjectDid: 'did:oan:registrar:one' });
  assert.equal(subject.status, 1);
  assert.equal(subject.version, 1);
  assert.deepEqual(subject.authorizedDomains, ['example.com']);
  assert.equal(logs[0][0], 'BulletinInitialized');
  assert.equal(logs[1][0], 'GovernanceExecution');
  const event = query('getExecutionEvent', { sequence: 1 });
  assert.equal(event.subjectDid, 'did:oan:registrar:one');
  assert.equal(event.subjectStatus, 1);
  assert.equal(query('getProposalStatus', { proposalId: Number(id) }), 2);
  assert.equal(query('getMemberStatus', { committeeType: 2, address: 'admin1' }), 1);
  assert.equal(query('getSubjectVersion', { subjectType: 1, subjectDid: 'did:oan:registrar:one' }), 1);
  assert.deepEqual(query('getSubjectAuthorizedDomains', { subjectType: 1, subjectDid: 'did:oan:registrar:one' }), ['example.com']);
  assert.equal(query('getSubjectStatus', { subjectType: 2, subjectDid: 'did:oan:missing' }), 0);
  assert.equal(query('getSubjectDid', { subjectType: 2, subjectDid: 'did:oan:missing' }), '');
});

test('approved stale authorization is rejected', () => {
  const { invoke, query } = harness();
  const first = Number(invoke('admin1', 'createProposal', registrarProposal()));
  const stale = Number(invoke('admin2', 'createProposal', registrarProposal()));
  for (const admin of ['admin1', 'admin2', 'admin3']) {
    invoke(admin, 'vote', { proposalId: first, approve: true });
    invoke(admin, 'vote', { proposalId: stale, approve: true });
  }
  invoke('admin4', 'refreshProposalStatus', { proposalId: first });
  invoke('admin4', 'refreshProposalStatus', { proposalId: stale });
  assert.equal(query('getProposal', { proposalId: stale }).status, 4);
});

test('domain updates preserve timing and increment the subject version', () => {
  const { invoke, query } = harness();
  const authorize = Number(invoke('admin1', 'createProposal', registrarProposal()));
  for (const admin of ['admin1', 'admin2', 'admin3']) invoke(admin, 'vote', { proposalId: authorize, approve: true });
  invoke('admin4', 'refreshProposalStatus', { proposalId: authorize });

  const update = Number(invoke('admin1', 'createProposal', registrarProposal({ actionType: 25, authorizedDomains: ['api.example.com', 'example.com'], policyHash: 'policy-2' })));
  for (const admin of ['admin1', 'admin2', 'admin3']) invoke(admin, 'vote', { proposalId: update, approve: true });
  invoke('admin4', 'refreshProposalStatus', { proposalId: update });
  const subject = query('getSubject', { subjectType: 1, subjectDid: 'did:oan:registrar:one' });
  assert.deepEqual(subject.authorizedDomains, ['api.example.com', 'example.com']);
  assert.equal(subject.policyHash, 'policy-2');
  assert.equal(subject.version, 2);
});

test('threshold changes do not alter the approval snapshot of an existing proposal', () => {
  const { invoke, query } = harness();
  const subjectId = Number(invoke('admin1', 'createProposal', registrarProposal()));
  const thresholdId = Number(invoke('meta1', 'createProposal', registrarProposal({
    committeeType: 1, actionType: 15, targetAddress: '', targetDid: '',
    subjectType: 0, authorizedDomains: [], thresholdValue: 1,
  })));
  for (const meta of ['meta1', 'meta2', 'meta3']) invoke(meta, 'vote', { proposalId: thresholdId, approve: true });
  invoke('meta4', 'refreshProposalStatus', { proposalId: thresholdId });
  invoke('admin1', 'vote', { proposalId: subjectId, approve: true });
  invoke('admin2', 'refreshProposalStatus', { proposalId: subjectId });
  const proposalState = query('getProposal', { proposalId: subjectId });
  assert.equal(proposalState.requiredApprovals, 3);
  assert.equal(proposalState.status, 1);
});

test('proposal expiration uses the Sui millisecond voting window', () => {
  const { invoke, query } = harness();
  const createdAt = 1_700_000_000_000;
  const id = Number(invoke('admin1', 'createProposal', registrarProposal(), createdAt));
  invoke('admin2', 'refreshProposalStatus', { proposalId: id }, createdAt + 864_000_001);
  assert.equal(query('getProposalStatus', { proposalId: id }), 3);
});
