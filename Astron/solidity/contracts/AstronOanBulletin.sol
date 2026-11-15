// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

pragma solidity >=0.8.20 <0.9.0;

import "../../../Ethereum/contracts/OanBulletin.sol";

contract AstronOanBulletin is OanBulletin {
    constructor(
        string memory rootAuthorityDid,
        address[] memory metaAdmins,
        address[] memory admins,
        uint256 adminThreshold
    ) OanBulletin(rootAuthorityDid, metaAdmins, admins, adminThreshold) {}
}
