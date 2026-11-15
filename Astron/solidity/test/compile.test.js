// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const solc = require('solc');
const solcBif = require('@bifproject/solc-bif');

function compilerInput() {
  const adapterPath = path.join(__dirname, '..', 'contracts', 'AstronOanBulletin.sol');
  const basePath = path.join(__dirname, '..', '..', '..', 'Ethereum', 'contracts', 'OanBulletin.sol');
  return {
    language: 'Solidity',
    sources: {
      'Astron/solidity/contracts/AstronOanBulletin.sol': { content: fs.readFileSync(adapterPath, 'utf8') },
      'Ethereum/contracts/OanBulletin.sol': { content: fs.readFileSync(basePath, 'utf8') },
    },
    settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { '*': { '*': ['abi', 'evm.bytecode'] } } },
  };
}

function assertCompiles(compiler, label) {
  const output = JSON.parse(compiler.compile(JSON.stringify(compilerInput())));
  const errors = (output.errors || []).filter((entry) => entry.severity === 'error');
  assert.deepEqual(errors, [], `${label}\n${errors.map((entry) => entry.formattedMessage).join('\n')}`);
  assert.ok(output.contracts['Astron/solidity/contracts/AstronOanBulletin.sol'].AstronOanBulletin.evm.bytecode.object.length > 0);
}

test('Astron adapter and shared governance contract compile with upstream Solidity 0.8.21', () => {
  assertCompiles(solc, 'upstream solc');
});

test('Astron adapter compiles with the official BIF Solidity compiler', () => {
  assertCompiles(solcBif, 'solc-bif');
});
