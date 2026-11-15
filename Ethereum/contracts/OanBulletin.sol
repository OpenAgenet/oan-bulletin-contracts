// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

pragma solidity >=0.8.20 <0.9.0;

contract OanBulletin {
    uint8 public constant MEMBER_ACTIVE = 1;
    uint8 public constant MEMBER_DISABLED = 2;
    uint8 public constant MEMBER_REMOVED = 3;

    uint8 public constant SUBJECT_NONE = 0;
    uint8 public constant SUBJECT_REGISTRAR = 1;
    uint8 public constant SUBJECT_DISCOVERY = 2;
    uint8 public constant SUBJECT_VC_ISSUER = 3;

    uint8 public constant SUBJECT_ACTIVE = 1;
    uint8 public constant SUBJECT_SUSPENDED = 2;
    uint8 public constant SUBJECT_REVOKED = 3;

    uint8 public constant COMMITTEE_META_ADMIN = 1;
    uint8 public constant COMMITTEE_ADMIN = 2;

    uint8 public constant ACTION_META_ADD = 1;
    uint8 public constant ACTION_META_DISABLE = 2;
    uint8 public constant ACTION_META_ENABLE = 3;
    uint8 public constant ACTION_META_REMOVE = 4;
    uint8 public constant ACTION_ADMIN_ADD = 11;
    uint8 public constant ACTION_ADMIN_DISABLE = 12;
    uint8 public constant ACTION_ADMIN_ENABLE = 13;
    uint8 public constant ACTION_ADMIN_REMOVE = 14;
    uint8 public constant ACTION_ADMIN_THRESHOLD_UPDATE = 15;
    uint8 public constant ACTION_REGISTRAR_AUTHORIZE = 21;
    uint8 public constant ACTION_REGISTRAR_SUSPEND = 22;
    uint8 public constant ACTION_REGISTRAR_RECOVER = 23;
    uint8 public constant ACTION_REGISTRAR_REVOKE = 24;
    uint8 public constant ACTION_REGISTRAR_DOMAINS_UPDATE = 25;
    uint8 public constant ACTION_DISCOVERY_AUTHORIZE = 31;
    uint8 public constant ACTION_DISCOVERY_DOMAINS_UPDATE = 32;
    uint8 public constant ACTION_DISCOVERY_SUSPEND = 33;
    uint8 public constant ACTION_DISCOVERY_RECOVER = 34;
    uint8 public constant ACTION_DISCOVERY_REVOKE = 35;
    uint8 public constant ACTION_VC_ISSUER_AUTHORIZE = 41;
    uint8 public constant ACTION_VC_ISSUER_SUSPEND = 42;
    uint8 public constant ACTION_VC_ISSUER_RECOVER = 43;
    uint8 public constant ACTION_VC_ISSUER_REVOKE = 44;
    uint8 public constant ACTION_ROOT_DID_ROTATE = 51;

    uint8 public constant PROPOSAL_PENDING = 1;
    uint8 public constant PROPOSAL_PASSED = 2;
    uint8 public constant PROPOSAL_EXPIRED = 3;
    uint8 public constant PROPOSAL_REJECTED = 4;

    uint256 public constant MIN_ACTIVE_META_ADMINS = 4;
    uint256 public constant MIN_ACTIVE_ADMINS = 4;
    uint256 public constant MAX_CONFIGURED_META_ADMINS = 15;
    uint256 public constant MAX_CONFIGURED_ADMINS = 25;
    uint256 public constant MAX_VOTING_WINDOW_MS = 864000000;
    uint256 public constant MAX_PENDING_PROPOSALS = 256;
    uint256 public constant MAX_TOTAL_PROPOSALS = 300;
    uint256 public constant MAX_DID_BYTES = 256;
    uint256 public constant MAX_DOMAIN_COUNT = 116;
    uint256 public constant MAX_DOMAIN_BYTES = 128;
    uint256 public constant MAX_HASH_BYTES = 256;
    uint256 public constant MAX_ROOT_AUTHORITY_DID_BYTES = 128;

    struct Member {
        address account;
        uint8 status;
    }

    struct ProposalInput {
        uint8 committeeType;
        uint8 actionType;
        address targetAddress;
        string targetDid;
        uint8 subjectType;
        string[] authorizedDomains;
        bytes policyHash;
        bytes metadataHash;
        bytes paramsHash;
        uint256 effectiveFromMs;
        uint256 subjectExpiryMs;
        uint256 thresholdValue;
    }

    struct Proposal {
        uint256 proposalId;
        uint8 committeeType;
        uint8 actionType;
        uint8 subjectType;
        address targetAddress;
        string targetDid;
        string[] authorizedDomains;
        bytes policyHash;
        bytes metadataHash;
        bytes paramsHash;
        address createdBy;
        uint256 createdAtMs;
        uint256 expiresAtMs;
        uint256 effectiveFromMs;
        uint256 subjectExpiryMs;
        uint256 thresholdValue;
        uint256 requiredApprovals;
        uint8 status;
        uint256 approvals;
        uint256 rejections;
        uint256 finalizedAtMs;
        mapping(address => bool) voted;
    }

    struct SubjectState {
        string subjectDid;
        uint8 subjectType;
        uint8 status;
        string[] authorizedDomains;
        bytes policyHash;
        bytes metadataHash;
        uint256 effectiveFromMs;
        uint256 expiresAtMs;
        uint256 version;
        uint256 updatedAtMs;
        bool exists;
    }

    struct ExecutionSnapshot {
        string rootDid;
        uint8 subjectStatus;
        string[] domains;
        uint256 effectiveFromMs;
        uint256 expiresAtMs;
        bytes policyHash;
        bytes metadataHash;
    }

    event BulletinInitialized(
        string rootAuthorityDid,
        address[] metaAdmins,
        address[] admins,
        uint256 adminThreshold,
        address publisher
    );

    event GovernanceExecution(
        uint8 indexed eventType,
        uint256 indexed sequence,
        uint256 indexed proposalId,
        bytes32 previousEventDigest,
        bytes32 eventDigest,
        bytes payload
    );

    string public rootAuthorityDid;
    address public immutable publisher;
    uint256 public adminThreshold;
    uint256 public nextProposalId = 1;
    uint256 public latestEventSequence;
    bytes32 public lastEventDigest;
    uint256 public lastClockMs;

    Member[] private _metaAdmins;
    Member[] private _admins;
    mapping(address => uint256) private _metaAdminIndexPlusOne;
    mapping(address => uint256) private _adminIndexPlusOne;
    mapping(uint256 => Proposal) private _proposals;
    uint256[] private _proposalIds;
    uint256 private _pendingProposalCount;
    mapping(bytes32 => SubjectState) private _subjects;

    constructor(
        string memory rootAuthorityDid_,
        address[] memory metaAdmins_,
        address[] memory admins_,
        uint256 adminThreshold_
    ) {
        require(bytes(rootAuthorityDid_).length > 0, "empty root DID");
        require(bytes(rootAuthorityDid_).length <= MAX_ROOT_AUTHORITY_DID_BYTES, "root DID too large");
        require(metaAdmins_.length >= MIN_ACTIVE_META_ADMINS, "too few meta admins");
        require(admins_.length >= MIN_ACTIVE_ADMINS, "too few admins");
        require(metaAdmins_.length <= MAX_CONFIGURED_META_ADMINS, "too many meta admins");
        require(admins_.length <= MAX_CONFIGURED_ADMINS, "too many admins");
        _addInitialMembers(metaAdmins_, true);
        _addInitialMembers(admins_, false);
        _validateAdminThreshold(adminThreshold_, admins_.length);
        rootAuthorityDid = rootAuthorityDid_;
        adminThreshold = adminThreshold_;
        publisher = msg.sender;
        emit BulletinInitialized(rootAuthorityDid_, metaAdmins_, admins_, adminThreshold_, msg.sender);
    }

    function createProposal(ProposalInput calldata input) external returns (uint256 proposalId) {
        uint8 expectedCommittee = _expectedCommitteeForAction(input.actionType);
        require(input.committeeType == expectedCommittee, "invalid committee");
        _assertActiveMember(input.committeeType, msg.sender);
        _validateActionSubject(input.actionType, input.subjectType);
        uint256 nowMs = _nowMs();
        _touchClock(nowMs);
        if (input.actionType == ACTION_ROOT_DID_ROTATE) {
            require(input.targetAddress == address(0), "invalid root DID target");
            require(keccak256(bytes(input.targetDid)) != keccak256(bytes(rootAuthorityDid)), "root DID unchanged");
        }
        _validateProposalInputs(input, nowMs);
        require(_pendingProposalCount < MAX_PENDING_PROPOSALS, "too many pending proposals");
        _pruneFinalizedProposals();
        if (input.actionType == ACTION_ADMIN_THRESHOLD_UPDATE) {
            _validateAdminThreshold(input.thresholdValue, _countActive(_admins));
        }

        proposalId = nextProposalId++;
        Proposal storage proposal = _proposals[proposalId];
        proposal.proposalId = proposalId;
        proposal.committeeType = input.committeeType;
        proposal.actionType = input.actionType;
        proposal.subjectType = input.subjectType;
        proposal.targetAddress = input.targetAddress;
        proposal.targetDid = input.targetDid;
        _copyCalldataDomainsToStorage(proposal.authorizedDomains, input.authorizedDomains);
        proposal.policyHash = input.policyHash;
        proposal.metadataHash = input.metadataHash;
        proposal.paramsHash = input.paramsHash;
        proposal.createdBy = msg.sender;
        proposal.createdAtMs = nowMs;
        proposal.expiresAtMs = nowMs + MAX_VOTING_WINDOW_MS;
        proposal.effectiveFromMs = input.effectiveFromMs;
        proposal.subjectExpiryMs = input.subjectExpiryMs;
        proposal.thresholdValue = input.thresholdValue;
        proposal.requiredApprovals = _currentThreshold(input.committeeType);
        proposal.status = PROPOSAL_PENDING;
        _proposalIds.push(proposalId);
        _pendingProposalCount++;
    }

    function vote(uint256 proposalId, bool approve) external {
        Proposal storage proposal = _proposal(proposalId);
        uint256 nowMs = _nowMs();
        _touchClock(nowMs);
        _assertActiveMember(proposal.committeeType, msg.sender);
        require(proposal.status == PROPOSAL_PENDING, "proposal not pending");
        require(nowMs <= proposal.expiresAtMs, "proposal expired");
        require(!proposal.voted[msg.sender], "duplicate vote");
        proposal.voted[msg.sender] = true;
        if (approve) proposal.approvals++; else proposal.rejections++;
    }

    function refreshProposalStatus(uint256 proposalId) external {
        Proposal storage proposal = _proposal(proposalId);
        uint256 nowMs = _nowMs();
        _touchClock(nowMs);
        require(proposal.status == PROPOSAL_PENDING, "proposal not pending");
        if (proposal.approvals >= proposal.requiredApprovals) {
            proposal.finalizedAtMs = nowMs;
            _pendingProposalCount--;
            if (!_canApply(proposal)) {
                proposal.status = PROPOSAL_REJECTED;
                return;
            }
            proposal.status = PROPOSAL_PASSED;
            _apply(proposal, nowMs);
        } else if (nowMs > proposal.expiresAtMs) {
            proposal.status = PROPOSAL_EXPIRED;
            proposal.finalizedAtMs = nowMs;
            _pendingProposalCount--;
        }
    }

    function proposalSummary(uint256 proposalId) external view returns (
        uint8 status,
        uint256 approvals,
        uint256 rejections,
        uint256 requiredApprovals,
        uint256 expiresAtMs
    ) {
        Proposal storage proposal = _proposal(proposalId);
        return (proposal.status, proposal.approvals, proposal.rejections, proposal.requiredApprovals, proposal.expiresAtMs);
    }

    function proposalStatus(uint256 proposalId) external view returns (uint8) {
        return _proposal(proposalId).status;
    }

    function metaAdminCount() external view returns (uint256) { return _metaAdmins.length; }
    function adminCount() external view returns (uint256) { return _admins.length; }
    function metaAdminCountTotal() external view returns (uint256) { return _metaAdmins.length; }
    function adminCountTotal() external view returns (uint256) { return _admins.length; }
    function activeMetaAdminCount() external view returns (uint256) { return _countActive(_metaAdmins); }
    function activeAdminCount() external view returns (uint256) { return _countActive(_admins); }
    function metaAdminAt(uint256 index) external view returns (address, uint8) { Member storage m = _metaAdmins[index]; return (m.account, m.status); }
    function adminAt(uint256 index) external view returns (address, uint8) { Member storage m = _admins[index]; return (m.account, m.status); }

    function memberStatus(uint8 committeeType, address account) public view returns (uint8) {
        if (committeeType == COMMITTEE_META_ADMIN) {
            uint256 index = _metaAdminIndexPlusOne[account];
            require(index != 0, "member not found");
            return _metaAdmins[index - 1].status;
        }
        if (committeeType == COMMITTEE_ADMIN) {
            uint256 index = _adminIndexPlusOne[account];
            require(index != 0, "member not found");
            return _admins[index - 1].status;
        }
        revert("invalid committee");
    }

    function subjectSnapshot(uint8 subjectType, string calldata subjectDid_) external view returns (
        bool exists,
        uint8 status,
        uint256 version,
        uint256 effectiveFromMs,
        uint256 expiresAtMs
    ) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid_)];
        if (!subject.exists) return (false, SUBJECT_NONE, 0, 0, 0);
        return (true, subject.status, subject.version, subject.effectiveFromMs, subject.expiresAtMs);
    }

    function subjectIsAuthorizedAt(uint8 subjectType, string calldata subjectDid, uint256 atMs) external view returns (bool) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        return subject.exists && _isAuthorizedAt(subject, atMs);
    }

    function subjectStatus(uint8 subjectType, string calldata subjectDid) external view returns (uint8) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        return subject.exists ? subject.status : SUBJECT_NONE;
    }

    function subjectVersion(uint8 subjectType, string calldata subjectDid) external view returns (uint256) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        return subject.exists ? subject.version : 0;
    }

    function subjectDomainCount(uint8 subjectType, string calldata subjectDid) external view returns (uint256) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        return subject.exists ? subject.authorizedDomains.length : 0;
    }

    function subjectExists(uint8 subjectType, string calldata subjectDid) external view returns (bool) {
        return _subjects[_subjectKey(subjectType, subjectDid)].exists;
    }

    function subjectDid(uint8 subjectType, string calldata subjectDid_) external view returns (string memory) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid_)];
        return subject.exists ? subject.subjectDid : "";
    }

    function subjectAuthorizationSnapshotAt(uint8 subjectType, string calldata subjectDid, uint256 atMs) external view returns (
        bool exists,
        bool authorized,
        uint8 status,
        uint256 version,
        uint256 effectiveFromMs,
        uint256 expiresAtMs
    ) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        if (!subject.exists) return (false, false, SUBJECT_NONE, 0, 0, 0);
        return (true, _isAuthorizedAt(subject, atMs), subject.status, subject.version, subject.effectiveFromMs, subject.expiresAtMs);
    }

    function subjectPolicyHash(uint8 subjectType, string calldata subjectDid) external view returns (bytes memory) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        return subject.exists ? subject.policyHash : bytes("");
    }

    function subjectMetadataHash(uint8 subjectType, string calldata subjectDid) external view returns (bytes memory) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        return subject.exists ? subject.metadataHash : bytes("");
    }

    function subjectAuthorizedDomains(uint8 subjectType, string calldata subjectDid) external view returns (string[] memory) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        return subject.exists ? subject.authorizedDomains : new string[](0);
    }

    function registrarIsAuthorizedAt(string calldata subjectDid, uint256 atMs) external view returns (bool) {
        SubjectState storage subject = _subjects[_subjectKey(SUBJECT_REGISTRAR, subjectDid)];
        return subject.exists && _isAuthorizedAt(subject, atMs);
    }

    function discoveryIsAuthorizedAt(string calldata subjectDid, uint256 atMs) external view returns (bool) {
        SubjectState storage subject = _subjects[_subjectKey(SUBJECT_DISCOVERY, subjectDid)];
        return subject.exists && _isAuthorizedAt(subject, atMs);
    }

    function vcIssuerIsAuthorizedAt(string calldata subjectDid, uint256 atMs) external view returns (bool) {
        SubjectState storage subject = _subjects[_subjectKey(SUBJECT_VC_ISSUER, subjectDid)];
        return subject.exists && _isAuthorizedAt(subject, atMs);
    }

    function subjectDetails(uint8 subjectType, string calldata subjectDid) external view returns (
        string[] memory authorizedDomains,
        bytes memory policyHash,
        bytes memory metadataHash,
        uint256 updatedAtMs
    ) {
        SubjectState storage subject = _subjects[_subjectKey(subjectType, subjectDid)];
        require(subject.exists, "subject not found");
        return (subject.authorizedDomains, subject.policyHash, subject.metadataHash, subject.updatedAtMs);
    }

    function _addInitialMembers(address[] memory accounts, bool meta) private {
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "zero member");
            if (meta) {
                require(_metaAdminIndexPlusOne[accounts[i]] == 0, "duplicate member");
                _metaAdmins.push(Member(accounts[i], MEMBER_ACTIVE));
                _metaAdminIndexPlusOne[accounts[i]] = _metaAdmins.length;
            } else {
                require(_adminIndexPlusOne[accounts[i]] == 0, "duplicate member");
                _admins.push(Member(accounts[i], MEMBER_ACTIVE));
                _adminIndexPlusOne[accounts[i]] = _admins.length;
            }
        }
    }

    function _validateProposalInputs(ProposalInput calldata input, uint256 nowMs) private pure {
        require(input.metadataHash.length > 0 && input.paramsHash.length > 0, "required hash empty");
        require(input.policyHash.length <= MAX_HASH_BYTES && input.metadataHash.length <= MAX_HASH_BYTES && input.paramsHash.length <= MAX_HASH_BYTES, "hash too large");
        bytes memory did = bytes(input.targetDid);
        if (input.subjectType == SUBJECT_NONE) {
            if (input.actionType == ACTION_ROOT_DID_ROTATE) require(did.length > 0 && did.length <= MAX_ROOT_AUTHORITY_DID_BYTES, "invalid root DID");
            else require(did.length == 0, "unexpected DID");
            require(input.authorizedDomains.length == 0, "unexpected domains");
            return;
        }
        require(did.length > 0, "empty subject DID");
        require(did.length <= MAX_DID_BYTES, "DID too large");
        require(input.effectiveFromMs == 0 || input.effectiveFromMs <= nowMs, "invalid effective time");
        require(input.subjectExpiryMs == 0 || input.subjectExpiryMs > nowMs, "invalid expiry");
        require(input.subjectExpiryMs == 0 || input.effectiveFromMs <= input.subjectExpiryMs, "invalid timing");
        bool domainsAction = input.actionType == ACTION_REGISTRAR_AUTHORIZE || input.actionType == ACTION_REGISTRAR_DOMAINS_UPDATE || input.actionType == ACTION_DISCOVERY_AUTHORIZE || input.actionType == ACTION_DISCOVERY_DOMAINS_UPDATE;
        if (domainsAction) _validateDomains(input.authorizedDomains); else require(input.authorizedDomains.length == 0, "unexpected domains");
    }

    function _validateDomains(string[] calldata domains) private pure {
        require(domains.length > 0, "empty domains");
        require(domains.length <= MAX_DOMAIN_COUNT, "too many domains");
        for (uint256 i = 0; i < domains.length; i++) {
            bytes calldata domain = bytes(domains[i]);
            require(domain.length > 0 && domain.length <= MAX_DOMAIN_BYTES, "invalid domain length");
            for (uint256 j = 0; j < domain.length; j++) require(domain[j] < 0x41 || domain[j] > 0x5a, "domain not canonical");
            if (domain.length == 1 && domain[0] == 0x2a) require(domains.length == 1, "wildcard mixed");
            if (i > 0) require(_compareBytes(bytes(domains[i - 1]), domain) < 0, "domains unsorted");
        }
    }

    function _validateActionSubject(uint8 actionType, uint8 subjectType) private pure {
        if (_isMemberAction(actionType) || actionType == ACTION_ADMIN_THRESHOLD_UPDATE || actionType == ACTION_ROOT_DID_ROTATE) require(subjectType == SUBJECT_NONE, "invalid subject type");
        else if (actionType >= 21 && actionType <= 25) require(subjectType == SUBJECT_REGISTRAR, "invalid subject type");
        else if (actionType >= 31 && actionType <= 35) require(subjectType == SUBJECT_DISCOVERY, "invalid subject type");
        else if (actionType >= 41 && actionType <= 44) require(subjectType == SUBJECT_VC_ISSUER, "invalid subject type");
        else revert("invalid action");
    }

    function _expectedCommitteeForAction(uint8 actionType) private pure returns (uint8) {
        if (_isMemberAction(actionType) || actionType == ACTION_ADMIN_THRESHOLD_UPDATE || actionType == ACTION_ROOT_DID_ROTATE) return COMMITTEE_META_ADMIN;
        if ((actionType >= 21 && actionType <= 25) || (actionType >= 31 && actionType <= 35) || (actionType >= 41 && actionType <= 44)) return COMMITTEE_ADMIN;
        revert("invalid action");
    }

    function _isMemberAction(uint8 actionType) private pure returns (bool) {
        return (actionType >= 1 && actionType <= 4) || (actionType >= 11 && actionType <= 14);
    }

    function _canApply(Proposal storage p) private view returns (bool) {
        if (p.actionType == ACTION_META_ADD) return _metaAdminIndexPlusOne[p.targetAddress] == 0 && _countConfigured(_metaAdmins) < MAX_CONFIGURED_META_ADMINS;
        if (p.actionType == ACTION_META_DISABLE || p.actionType == ACTION_META_REMOVE) return _canDeactivate(_metaAdmins, _metaAdminIndexPlusOne[p.targetAddress], MIN_ACTIVE_META_ADMINS);
        if (p.actionType == ACTION_META_ENABLE) return _hasStatus(_metaAdmins, _metaAdminIndexPlusOne[p.targetAddress], MEMBER_DISABLED);
        if (p.actionType == ACTION_ADMIN_ADD) return _adminIndexPlusOne[p.targetAddress] == 0 && _countConfigured(_admins) < MAX_CONFIGURED_ADMINS;
        if (p.actionType == ACTION_ADMIN_DISABLE || p.actionType == ACTION_ADMIN_REMOVE) return _canDeactivate(_admins, _adminIndexPlusOne[p.targetAddress], MIN_ACTIVE_ADMINS);
        if (p.actionType == ACTION_ADMIN_ENABLE) return _hasStatus(_admins, _adminIndexPlusOne[p.targetAddress], MEMBER_DISABLED);
        if (p.actionType == ACTION_ADMIN_THRESHOLD_UPDATE) return p.thresholdValue >= 1 && p.thresholdValue <= _maxThreshold(_countActive(_admins));
        if (p.actionType == ACTION_ROOT_DID_ROTATE) return keccak256(bytes(p.targetDid)) != keccak256(bytes(rootAuthorityDid));
        SubjectState storage subject = _subjects[_subjectKey(p.subjectType, p.targetDid)];
        if (_isAuthorizeAction(p.actionType)) return !subject.exists;
        if (_isDomainsUpdateAction(p.actionType) || _isSuspendAction(p.actionType)) return subject.exists && subject.status == SUBJECT_ACTIVE;
        if (_isRecoverAction(p.actionType)) return subject.exists && subject.status == SUBJECT_SUSPENDED;
        if (_isRevokeAction(p.actionType)) return subject.exists && (subject.status == SUBJECT_ACTIVE || subject.status == SUBJECT_SUSPENDED);
        return false;
    }

    function _apply(Proposal storage p, uint256 nowMs) private {
        if (p.actionType == ACTION_META_ADD) _addMember(_metaAdmins, _metaAdminIndexPlusOne, p.targetAddress, MAX_CONFIGURED_META_ADMINS);
        else if (p.actionType == ACTION_META_DISABLE) _deactivate(_metaAdmins, _metaAdminIndexPlusOne[p.targetAddress], MEMBER_DISABLED, MIN_ACTIVE_META_ADMINS);
        else if (p.actionType == ACTION_META_ENABLE) _enable(_metaAdmins, _metaAdminIndexPlusOne[p.targetAddress]);
        else if (p.actionType == ACTION_META_REMOVE) _deactivate(_metaAdmins, _metaAdminIndexPlusOne[p.targetAddress], MEMBER_REMOVED, MIN_ACTIVE_META_ADMINS);
        else if (p.actionType == ACTION_ADMIN_ADD) _addMember(_admins, _adminIndexPlusOne, p.targetAddress, MAX_CONFIGURED_ADMINS);
        else if (p.actionType == ACTION_ADMIN_DISABLE) _deactivate(_admins, _adminIndexPlusOne[p.targetAddress], MEMBER_DISABLED, MIN_ACTIVE_ADMINS);
        else if (p.actionType == ACTION_ADMIN_ENABLE) _enable(_admins, _adminIndexPlusOne[p.targetAddress]);
        else if (p.actionType == ACTION_ADMIN_REMOVE) _deactivate(_admins, _adminIndexPlusOne[p.targetAddress], MEMBER_REMOVED, MIN_ACTIVE_ADMINS);
        else if (p.actionType == ACTION_ADMIN_THRESHOLD_UPDATE) adminThreshold = p.thresholdValue;
        else if (p.actionType == ACTION_ROOT_DID_ROTATE) {
            string memory previousRootDid = rootAuthorityDid;
            rootAuthorityDid = p.targetDid;
            _emitRootRotation(p, nowMs, previousRootDid);
            return;
        } else _applySubject(p, nowMs);

        if (p.subjectType == SUBJECT_NONE) _emitNoSubject(p, nowMs);
        else _emitSubject(p, nowMs, _subjects[_subjectKey(p.subjectType, p.targetDid)]);
    }

    function _applySubject(Proposal storage p, uint256 nowMs) private {
        SubjectState storage subject = _subjects[_subjectKey(p.subjectType, p.targetDid)];
        if (_isAuthorizeAction(p.actionType)) {
            subject.subjectDid = p.targetDid;
            subject.subjectType = p.subjectType;
            subject.status = SUBJECT_ACTIVE;
            subject.authorizedDomains = p.authorizedDomains;
            subject.policyHash = p.policyHash;
            subject.metadataHash = p.metadataHash;
            subject.effectiveFromMs = p.effectiveFromMs;
            subject.expiresAtMs = p.subjectExpiryMs;
            subject.version = 1;
            subject.updatedAtMs = nowMs;
            subject.exists = true;
        } else if (_isDomainsUpdateAction(p.actionType)) {
            subject.authorizedDomains = p.authorizedDomains;
            subject.policyHash = p.policyHash;
            subject.metadataHash = p.metadataHash;
            subject.version++;
            subject.updatedAtMs = nowMs;
        } else {
            if (_isSuspendAction(p.actionType)) subject.status = SUBJECT_SUSPENDED;
            else if (_isRecoverAction(p.actionType)) subject.status = SUBJECT_ACTIVE;
            else if (_isRevokeAction(p.actionType)) subject.status = SUBJECT_REVOKED;
            else revert("invalid action");
            subject.policyHash = p.policyHash;
            subject.metadataHash = p.metadataHash;
            subject.version++;
            subject.updatedAtMs = nowMs;
        }
    }

    function _emitRootRotation(Proposal storage p, uint256 nowMs, string memory previousRootDid) private {
        ExecutionSnapshot memory snapshot;
        snapshot.rootDid = previousRootDid;
        snapshot.subjectStatus = SUBJECT_NONE;
        snapshot.domains = new string[](0);
        snapshot.policyHash = p.policyHash;
        snapshot.metadataHash = p.metadataHash;
        _emitExecution(p, nowMs, snapshot);
    }

    function _emitNoSubject(Proposal storage p, uint256 nowMs) private {
        ExecutionSnapshot memory snapshot;
        snapshot.rootDid = rootAuthorityDid;
        snapshot.subjectStatus = SUBJECT_NONE;
        snapshot.domains = new string[](0);
        snapshot.policyHash = p.policyHash;
        snapshot.metadataHash = p.metadataHash;
        _emitExecution(p, nowMs, snapshot);
    }

    function _emitSubject(Proposal storage p, uint256 nowMs, SubjectState storage subject) private {
        ExecutionSnapshot memory snapshot;
        snapshot.rootDid = rootAuthorityDid;
        snapshot.subjectStatus = subject.status;
        snapshot.domains = subject.authorizedDomains;
        snapshot.effectiveFromMs = subject.effectiveFromMs;
        snapshot.expiresAtMs = subject.expiresAtMs;
        snapshot.policyHash = subject.policyHash;
        snapshot.metadataHash = subject.metadataHash;
        _emitExecution(p, nowMs, snapshot);
    }

    function _emitExecution(Proposal storage p, uint256 nowMs, ExecutionSnapshot memory snapshot) private {
        uint256 sequence = ++latestEventSequence;
        bytes32 previous = lastEventDigest;
        bytes memory payload = abi.encode(
            snapshot.rootDid,
            p.committeeType,
            p.targetAddress,
            p.targetDid,
            p.subjectType,
            snapshot.subjectStatus,
            snapshot.domains,
            snapshot.effectiveFromMs,
            snapshot.expiresAtMs,
            snapshot.policyHash,
            snapshot.metadataHash,
            nowMs
        );
        bytes32 digest = keccak256(abi.encode(sequence, p.actionType, p.proposalId, previous, payload));
        lastEventDigest = digest;
        emit GovernanceExecution(p.actionType, sequence, p.proposalId, previous, digest, payload);
    }

    function _addMember(Member[] storage members, mapping(address => uint256) storage indexes, address account, uint256 maxMembers) private {
        require(account != address(0) && indexes[account] == 0, "duplicate member");
        require(_countConfigured(members) < maxMembers, "too many members");
        members.push(Member(account, MEMBER_ACTIVE));
        indexes[account] = members.length;
    }

    function _copyCalldataDomainsToStorage(string[] storage target, string[] calldata source) private {
        for (uint256 i = 0; i < source.length; i++) target.push(source[i]);
    }

    function _deactivate(Member[] storage members, uint256 indexPlusOne, uint8 nextStatus, uint256 minimumActive) private {
        require(indexPlusOne != 0, "member not found");
        Member storage member = members[indexPlusOne - 1];
        require(member.status == MEMBER_ACTIVE, "invalid member status");
        require(_countActive(members) > minimumActive, "below minimum active");
        member.status = nextStatus;
    }

    function _enable(Member[] storage members, uint256 indexPlusOne) private {
        require(indexPlusOne != 0, "member not found");
        Member storage member = members[indexPlusOne - 1];
        require(member.status == MEMBER_DISABLED, "invalid member status");
        member.status = MEMBER_ACTIVE;
    }

    function _canDeactivate(Member[] storage members, uint256 indexPlusOne, uint256 minimumActive) private view returns (bool) {
        return indexPlusOne != 0 && members[indexPlusOne - 1].status == MEMBER_ACTIVE && _countActive(members) > minimumActive;
    }

    function _hasStatus(Member[] storage members, uint256 indexPlusOne, uint8 status) private view returns (bool) {
        return indexPlusOne != 0 && members[indexPlusOne - 1].status == status;
    }

    function _countActive(Member[] storage members) private view returns (uint256 count) {
        for (uint256 i = 0; i < members.length; i++) if (members[i].status == MEMBER_ACTIVE) count++;
    }

    function _countConfigured(Member[] storage members) private view returns (uint256 count) {
        for (uint256 i = 0; i < members.length; i++) if (members[i].status != MEMBER_REMOVED) count++;
    }

    function _currentThreshold(uint8 committeeType) private view returns (uint256) {
        return committeeType == COMMITTEE_META_ADMIN ? _maxThreshold(_countActive(_metaAdmins)) : adminThreshold;
    }

    function _maxThreshold(uint256 activeCount) private pure returns (uint256) { return (activeCount * 2) / 3 + 1; }

    function _validateAdminThreshold(uint256 threshold, uint256 activeCount) private pure {
        require(threshold >= 1 && threshold <= _maxThreshold(activeCount), "invalid threshold");
    }

    function _assertActiveMember(uint8 committeeType, address account) private view {
        require(memberStatus(committeeType, account) == MEMBER_ACTIVE, "not active member");
    }

    function _proposal(uint256 proposalId) private view returns (Proposal storage proposal) {
        proposal = _proposals[proposalId];
        require(proposal.proposalId != 0, "proposal not found");
    }

    function _pruneFinalizedProposals() private {
        while (_proposalIds.length >= MAX_TOTAL_PROPOSALS) {
            bool found;
            uint256 foundIndex;
            uint256 oldestId;
            for (uint256 i = 0; i < _proposalIds.length; i++) {
                uint256 candidateId = _proposalIds[i];
                if (_proposals[candidateId].status != PROPOSAL_PENDING && (!found || candidateId < oldestId)) {
                    found = true;
                    foundIndex = i;
                    oldestId = candidateId;
                }
            }
            if (!found) return;
            delete _proposals[_proposalIds[foundIndex]];
            for (uint256 i = foundIndex; i + 1 < _proposalIds.length; i++) _proposalIds[i] = _proposalIds[i + 1];
            _proposalIds.pop();
        }
    }

    function _subjectKey(uint8 subjectType, string memory did) private pure returns (bytes32) { return keccak256(abi.encode(subjectType, did)); }

    function _isAuthorizedAt(SubjectState storage subject, uint256 atMs) private view returns (bool) {
        return subject.status == SUBJECT_ACTIVE && (subject.effectiveFromMs == 0 || subject.effectiveFromMs <= atMs) && (subject.expiresAtMs == 0 || atMs < subject.expiresAtMs);
    }

    function _isAuthorizeAction(uint8 actionType) private pure returns (bool) { return actionType == ACTION_REGISTRAR_AUTHORIZE || actionType == ACTION_DISCOVERY_AUTHORIZE || actionType == ACTION_VC_ISSUER_AUTHORIZE; }
    function _isDomainsUpdateAction(uint8 actionType) private pure returns (bool) { return actionType == ACTION_REGISTRAR_DOMAINS_UPDATE || actionType == ACTION_DISCOVERY_DOMAINS_UPDATE; }
    function _isSuspendAction(uint8 actionType) private pure returns (bool) { return actionType == ACTION_REGISTRAR_SUSPEND || actionType == ACTION_DISCOVERY_SUSPEND || actionType == ACTION_VC_ISSUER_SUSPEND; }
    function _isRecoverAction(uint8 actionType) private pure returns (bool) { return actionType == ACTION_REGISTRAR_RECOVER || actionType == ACTION_DISCOVERY_RECOVER || actionType == ACTION_VC_ISSUER_RECOVER; }
    function _isRevokeAction(uint8 actionType) private pure returns (bool) { return actionType == ACTION_REGISTRAR_REVOKE || actionType == ACTION_DISCOVERY_REVOKE || actionType == ACTION_VC_ISSUER_REVOKE; }

    function _compareBytes(bytes memory left, bytes memory right) private pure returns (int8) {
        uint256 length = left.length < right.length ? left.length : right.length;
        for (uint256 i = 0; i < length; i++) {
            if (left[i] < right[i]) return -1;
            if (left[i] > right[i]) return 1;
        }
        if (left.length < right.length) return -1;
        if (left.length > right.length) return 1;
        return 0;
    }

    function _touchClock(uint256 nowMs) private { require(nowMs >= lastClockMs, "clock regression"); lastClockMs = nowMs; }
    function _nowMs() private view returns (uint256) { return block.timestamp * 1000; }
}
