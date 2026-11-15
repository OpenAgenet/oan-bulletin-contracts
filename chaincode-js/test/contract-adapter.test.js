// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { OanBulletinContract } = require('../lib/bulletin-contract');

function context(identity = 'meta1') {
  const state = new Map();
  const events = [];
  return {
    state,
    events,
    ctx: {
      clientIdentity: { getID: () => identity },
      stub: {
        getState: async (key) => state.get(key) || Buffer.alloc(0),
        putState: async (key, value) => state.set(key, value),
        setEvent: (name, payload) => events.push({ name, payload: JSON.parse(payload.toString('utf8')) }),
        getTxTimestamp: () => ({ seconds: 1700000000, nanos: 0 }),
      },
    },
  };
}

test('Fabric adapter initializes once, emits the initialization event, and exposes member state', async () => {
  const contract = new OanBulletinContract();
  const fixture = context();
  await contract.Initialize(
    fixture.ctx,
    'did:oan:root',
    JSON.stringify(['meta1', 'meta2', 'meta3', 'meta4']),
    JSON.stringify(['admin1', 'admin2', 'admin3', 'admin4']),
    '3',
  );
  assert.equal(fixture.events[0].name, 'BulletinInitialized');
  assert.equal(fixture.events[0].payload.publisher, 'meta1');
  assert.equal(await contract.GetMemberStatus(fixture.ctx, '1', 'meta1'), '1');
  assert.equal(await contract.GetSubjectStatus(fixture.ctx, '2', 'did:oan:missing'), '0');
  assert.equal(await contract.GetSubjectDid(fixture.ctx, '2', 'did:oan:missing'), '');
  assert.equal(await contract.SubjectExists(fixture.ctx, '2', 'did:oan:missing'), 'false');
  await assert.rejects(() => contract.Initialize(fixture.ctx, 'did:oan:other', '[]', '[]', '1'), /already initialized/);
});
