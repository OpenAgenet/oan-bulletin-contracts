// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ganache = require('ganache');
const solc = require('solc');
const { BrowserProvider, ContractFactory } = require('ethers');

let compiledArtifact;

function compile() {
  if (compiledArtifact) return compiledArtifact;
  const source = fs.readFileSync(path.join(__dirname, '..', 'contracts', 'OanBulletin.sol'), 'utf8');
  const input = {
    language: 'Solidity',
    sources: { 'OanBulletin.sol': { content: source } },
    settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { '*': { '*': ['abi', 'evm.bytecode'] } } },
  };
  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = (output.errors || []).filter((entry) => entry.severity === 'error');
  assert.deepEqual(errors, [], errors.map((entry) => entry.formattedMessage).join('\n'));
  compiledArtifact = output.contracts['OanBulletin.sol'].OanBulletin;
  return compiledArtifact;
}

async function fixture() {
  const artifact = compile();
  const eip1193 = ganache.provider({ logging: { quiet: true }, wallet: { totalAccounts: 12 } });
  const provider = new BrowserProvider(eip1193);
  const signers = await Promise.all(Array.from({ length: 10 }, (_, index) => provider.getSigner(index)));
  const addresses = await Promise.all(signers.map((signer) => signer.getAddress()));
  const factory = new ContractFactory(artifact.abi, artifact.evm.bytecode.object, signers[0]);
  const contract = await factory.deploy('did:oan:root', addresses.slice(0, 4), addresses.slice(4, 8), 3);
  await contract.waitForDeployment();
  return { contract, signers, addresses, eip1193 };
}

function proposal(overrides = {}) {
  return {
    committeeType: 2,
    actionType: 21,
    targetAddress: overrides.targetAddress,
    targetDid: 'did:oan:registrar:one',
    subjectType: 1,
    authorizedDomains: ['example.com'],
    policyHash: '0x01',
    metadataHash: '0x02',
    paramsHash: '0x03',
    effectiveFromMs: 0,
    subjectExpiryMs: 0,
    thresholdValue: 0,
    ...overrides,
  };
}

async function approve(contract, signers, proposalId, signerIndexes) {
  for (const index of signerIndexes) await (await contract.connect(signers[index]).vote(proposalId, true, { gasLimit: 500_000 })).wait();
  await (await contract.refreshProposalStatus(proposalId, { gasLimit: 2_000_000 })).wait();
}

test('admin committee authorizes a registrar and records its lifecycle state', async () => {
  const { contract, signers, addresses } = await fixture();
  await (await contract.connect(signers[4]).createProposal(proposal({ targetAddress: addresses[8] }), { gasLimit: 2_000_000 })).wait();
  for (const signer of signers.slice(4, 7)) await (await contract.connect(signer).vote(1, true, { gasLimit: 500_000 })).wait();
  await (await contract.refreshProposalStatus(1, { gasLimit: 2_000_000 })).wait();

  const summary = await contract.proposalSummary(1);
  assert.equal(summary.status, 2n);
  assert.equal(summary.requiredApprovals, 3n);
  const snapshot = await contract.subjectSnapshot(1, 'did:oan:registrar:one');
  assert.equal(snapshot.exists, true);
  assert.equal(snapshot.status, 1n);
  assert.equal(snapshot.version, 1n);
  assert.equal(await contract.subjectIsAuthorizedAt(1, 'did:oan:registrar:one', 0), true);
  assert.equal(await contract.latestEventSequence(), 1n);
});

test('meta-admin committee rotates the root DID with a threshold snapshot', async () => {
  const { contract, signers } = await fixture();
  const input = proposal({
    committeeType: 1,
    actionType: 51,
    targetAddress: '0x0000000000000000000000000000000000000000',
    targetDid: 'did:oan:root:next',
    subjectType: 0,
    authorizedDomains: [],
  });
  await (await contract.connect(signers[0]).createProposal(input, { gasLimit: 2_000_000 })).wait();
  for (const signer of signers.slice(0, 3)) await (await contract.connect(signer).vote(1, true, { gasLimit: 500_000 })).wait();
  await (await contract.refreshProposalStatus(1, { gasLimit: 2_000_000 })).wait();
  assert.equal(await contract.rootAuthorityDid(), 'did:oan:root:next');
  assert.equal(await contract.latestEventSequence(), 1n);
});

test('domain update preserves authorization timing and exposes Sui-equivalent reads', async () => {
  const { contract, signers, addresses } = await fixture();
  await (await contract.connect(signers[4]).createProposal(proposal({ targetAddress: addresses[8] }), { gasLimit: 2_000_000 })).wait();
  await approve(contract, signers, 1, [4, 5, 6]);

  const update = proposal({
    actionType: 25,
    targetAddress: addresses[8],
    authorizedDomains: ['api.example.com', 'example.com'],
    policyHash: '0x04', metadataHash: '0x05', paramsHash: '0x06',
  });
  await (await contract.connect(signers[4]).createProposal(update, { gasLimit: 2_000_000 })).wait();
  await approve(contract, signers, 2, [4, 5, 6]);

  assert.equal(await contract.subjectStatus(1, 'did:oan:registrar:one'), 1n);
  assert.equal(await contract.subjectVersion(1, 'did:oan:registrar:one'), 2n);
  assert.equal(await contract.subjectDomainCount(1, 'did:oan:registrar:one'), 2n);
  assert.equal(await contract.subjectExists(1, 'did:oan:registrar:one'), true);
  assert.equal(await contract.subjectDid(1, 'did:oan:registrar:one'), 'did:oan:registrar:one');
  assert.deepEqual(Array.from(await contract.subjectAuthorizedDomains(1, 'did:oan:registrar:one')), ['api.example.com', 'example.com']);
  assert.equal(await contract.subjectPolicyHash(1, 'did:oan:registrar:one'), '0x04');
});

test('lowering the admin threshold does not alter an existing proposal snapshot', async () => {
  const { contract, signers, addresses } = await fixture();
  await (await contract.connect(signers[4]).createProposal(proposal({ targetAddress: addresses[8] }), { gasLimit: 2_000_000 })).wait();
  const lowerThreshold = proposal({
    committeeType: 1, actionType: 15, targetAddress: addresses[8], targetDid: '', subjectType: 0,
    authorizedDomains: [], thresholdValue: 1,
  });
  await (await contract.connect(signers[0]).createProposal(lowerThreshold, { gasLimit: 2_000_000 })).wait();
  await approve(contract, signers, 2, [0, 1, 2]);
  assert.equal(await contract.adminThreshold(), 1n);

  await (await contract.connect(signers[4]).vote(1, true, { gasLimit: 500_000 })).wait();
  await (await contract.refreshProposalStatus(1, { gasLimit: 2_000_000 })).wait();
  const summary = await contract.proposalSummary(1);
  assert.equal(summary.requiredApprovals, 3n);
  assert.equal(summary.status, 1n);
});

test('proposal expires after the Sui voting window', async () => {
  const { contract, signers, addresses, eip1193 } = await fixture();
  await (await contract.connect(signers[4]).createProposal(proposal({ targetAddress: addresses[8] }), { gasLimit: 2_000_000 })).wait();
  await eip1193.request({ method: 'evm_increaseTime', params: [864001] });
  await eip1193.request({ method: 'evm_mine', params: [] });
  await (await contract.refreshProposalStatus(1, { gasLimit: 2_000_000 })).wait();
  assert.equal(await contract.proposalStatus(1), 3n);
});
