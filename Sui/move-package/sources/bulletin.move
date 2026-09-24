// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

module oan_bulletin::bulletin;

use std::bcs;
use std::hash;
use std::option;
use std::type_name;
use std::vector;
use sui::clock::{Self as clock, Clock};
use sui::event;
use sui::object::{Self as object, UID};
use sui::package;
use sui::transfer;
use sui::tx_context::{Self as tx_context, TxContext};

const E_NOT_ACTIVE_MEMBER: u64 = 1;
const E_DUPLICATE_MEMBER: u64 = 2;
const E_TOO_FEW_META_ADMINS: u64 = 3;
const E_TOO_FEW_ADMINS: u64 = 4;
const E_INVALID_THRESHOLD: u64 = 5;
const E_PROPOSAL_NOT_FOUND: u64 = 6;
const E_DUPLICATE_VOTE: u64 = 7;
const E_PROPOSAL_NOT_PENDING: u64 = 8;
const E_PROPOSAL_EXPIRED: u64 = 9;
const E_INVALID_COMMITTEE: u64 = 10;
const E_INVALID_ACTION: u64 = 11;
const E_MEMBER_NOT_FOUND: u64 = 12;
const E_MEMBER_STATUS: u64 = 13;
const E_BELOW_MIN_ACTIVE: u64 = 14;
const E_SUBJECT_NOT_FOUND: u64 = 15;
const E_INVALID_SUBJECT_STATE: u64 = 16;
const E_INVALID_SUBJECT_TYPE: u64 = 17;
const E_CLOCK_REGRESSION: u64 = 18;
const E_TOO_MANY_META_ADMINS: u64 = 19;
const E_TOO_MANY_ADMINS: u64 = 20;
const E_TOO_MANY_PENDING_PROPOSALS: u64 = 21;
const E_INPUT_TOO_LARGE: u64 = 22;
const E_EMPTY_SUBJECT_DID: u64 = 23;
const E_INVALID_SUBJECT_TIMING: u64 = 24;
const E_EMPTY_AUTHORIZED_DOMAIN: u64 = 25;
const E_ALREADY_INITIALIZED: u64 = 26;
const E_NOT_PACKAGE_PUBLISHER: u64 = 27;
const E_NOT_INIT_PUBLISHER: u64 = 28;
const E_UPGRADE_CAP_PACKAGE_MISMATCH: u64 = 29;
const E_EMPTY_REQUIRED_HASH: u64 = 30;
const E_DUPLICATE_OR_UNSORTED_AUTHORIZED_DOMAIN: u64 = 31;
const E_NON_CANONICAL_AUTHORIZED_DOMAIN: u64 = 32;
const E_WILDCARD_MIXED_AUTHORIZED_DOMAIN: u64 = 33;

const MEMBER_ACTIVE: u8 = 1;
const MEMBER_DISABLED: u8 = 2;
const MEMBER_REMOVED: u8 = 3;

const SUBJECT_NONE: u8 = 0;
const SUBJECT_REGISTRAR: u8 = 1;
const SUBJECT_DISCOVERY: u8 = 2;
const SUBJECT_VC_ISSUER: u8 = 3;

const SUBJECT_ACTIVE: u8 = 1;
const SUBJECT_SUSPENDED: u8 = 2;
const SUBJECT_REVOKED: u8 = 3;

const COMMITTEE_META_ADMIN: u8 = 1;
const COMMITTEE_ADMIN: u8 = 2;

const ACTION_META_ADD: u8 = 1;
const ACTION_META_DISABLE: u8 = 2;
const ACTION_META_ENABLE: u8 = 3;
const ACTION_META_REMOVE: u8 = 4;
const ACTION_ADMIN_ADD: u8 = 11;
const ACTION_ADMIN_DISABLE: u8 = 12;
const ACTION_ADMIN_ENABLE: u8 = 13;
const ACTION_ADMIN_REMOVE: u8 = 14;
const ACTION_ADMIN_THRESHOLD_UPDATE: u8 = 15;
const ACTION_REGISTRAR_AUTHORIZE: u8 = 21;
const ACTION_REGISTRAR_SUSPEND: u8 = 22;
const ACTION_REGISTRAR_RECOVER: u8 = 23;
const ACTION_REGISTRAR_REVOKE: u8 = 24;
const ACTION_REGISTRAR_DOMAINS_UPDATE: u8 = 25;
const ACTION_DISCOVERY_AUTHORIZE: u8 = 31;
const ACTION_DISCOVERY_DOMAINS_UPDATE: u8 = 32;
const ACTION_DISCOVERY_SUSPEND: u8 = 33;
const ACTION_DISCOVERY_RECOVER: u8 = 34;
const ACTION_DISCOVERY_REVOKE: u8 = 35;
const ACTION_VC_ISSUER_AUTHORIZE: u8 = 41;
const ACTION_VC_ISSUER_SUSPEND: u8 = 42;
const ACTION_VC_ISSUER_RECOVER: u8 = 43;
const ACTION_VC_ISSUER_REVOKE: u8 = 44;

const PROPOSAL_PENDING: u8 = 1;
const PROPOSAL_PASSED: u8 = 2;
const PROPOSAL_EXPIRED_STATUS: u8 = 3;
const PROPOSAL_REJECTED_STATUS: u8 = 4;
const MIN_ACTIVE_META_ADMINS: u64 = 4;
const MIN_ACTIVE_ADMINS: u64 = 4;
const MAX_CONFIGURED_META_ADMINS: u64 = 15;
const MAX_CONFIGURED_ADMINS: u64 = 25;
const MAX_VOTING_WINDOW_MS: u64 = 864000000;
const MAX_PENDING_PROPOSAL_RECORDS: u64 = 256;
const MAX_TOTAL_PROPOSAL_RECORDS: u64 = 300;
const MAX_DID_BYTES: u64 = 256;
const MAX_DOMAIN_COUNT: u64 = 116;
const MAX_DOMAIN_BYTES: u64 = 128;
const MAX_HASH_BYTES: u64 = 256;
const MAX_ROOT_AUTHORITY_DID_BYTES: u64 = 128;

public struct BULLETIN has drop {}

public struct Member has copy, drop, store {
    addr: address,
    status: u8,
}

public struct Proposal has copy, drop, store {
    proposal_id: u64,
    committee_type: u8,
    action_type: u8,
    subject_type: u8,
    target_address: address,
    target_did: vector<u8>,
    authorized_domains: vector<vector<u8>>,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
    params_hash: vector<u8>,
    created_by: address,
    created_at_ms: u64,
    expires_at_ms: u64,
    effective_from_ms: u64,
    subject_expiry_ms: u64,
    threshold_value: u64,
    required_approvals: u64,
    status: u8,
    approvals: u64,
    rejections: u64,
    approval_voters: vector<address>,
    rejection_voters: vector<address>,
    finalized_at_ms: u64,
}

public struct SubjectState has copy, drop, store {
    subject_did: vector<u8>,
    subject_type: u8,
    status: u8,
    authorized_domains: vector<vector<u8>>,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
    effective_from_ms: u64,
    expires_at_ms: u64,
    version: u64,
    updated_at_ms: u64,
}

public struct GovernanceExecutionEvent has copy, drop {
    event_type: u8,
    sequence: u64,
    root_authority_did: vector<u8>,
    proposal_id: u64,
    committee_type: u8,
    target_address: address,
    subject_did: vector<u8>,
    subject_type: u8,
    subject_status: u8,
    authorized_domains: vector<vector<u8>>,
    effective_from_ms: u64,
    expires_at_ms: u64,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
    previous_event_digest: vector<u8>,
    event_digest: vector<u8>,
    emitted_at_ms: u64,
}

public struct BulletinInitializedEvent has copy, drop {
    root_authority_did: vector<u8>,
    meta_admins: vector<address>,
    admins: vector<address>,
    admin_threshold: u64,
    publisher: address,
    package_address: address,
}

public struct Bulletin has key {
    id: UID,
    root_authority_did: vector<u8>,
    meta_admins: vector<Member>,
    admins: vector<Member>,
    admin_threshold: u64,
    next_proposal_id: u64,
    next_event_sequence: u64,
    proposals: vector<Proposal>,
    subjects: vector<SubjectState>,
    last_event_digest: vector<u8>,
    last_clock_ms: u64,
}

public struct BulletinInitState has key {
    id: UID,
    initialized: bool,
    publisher: address,
    package_address: address,
}

public struct UpgradeManager has key, store {
    id: UID,
    publisher: address,
    cap: package::UpgradeCap,
}

fun init(_: BULLETIN, ctx: &mut TxContext) {
    transfer::share_object(BulletinInitState {
        id: object::new(ctx),
        initialized: false,
        publisher: tx_context::sender(ctx),
        package_address: type_name::defining_id<BULLETIN>(),
    });
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(BULLETIN {}, ctx);
}

#[test_only]
public fun override_init_package_address_for_testing(
    init_state: &mut BulletinInitState,
    package_address: address,
) {
    init_state.package_address = package_address;
}

#[allow(lint(self_transfer))]
public fun initialize(
    init_state: &mut BulletinInitState,
    root_authority_did: vector<u8>,
    meta_admins: vector<address>,
    admins: vector<address>,
    admin_threshold: u64,
    upgrade_cap: package::UpgradeCap,
    ctx: &mut TxContext,
) {
    assert!(!init_state.initialized, E_ALREADY_INITIALIZED);
    assert!(tx_context::sender(ctx) == init_state.publisher, E_NOT_INIT_PUBLISHER);
    assert!(upgrade_cap.package().to_address() == init_state.package_address, E_UPGRADE_CAP_PACKAGE_MISMATCH);
    let publisher = tx_context::sender(ctx);
    let package_address = init_state.package_address;
    let meta_admins_for_event = copy meta_admins;
    let admins_for_event = copy admins;
    let bulletin = new_bulletin(root_authority_did, meta_admins, admins, admin_threshold, ctx);
    let upgrade_manager = new_upgrade_manager(publisher, upgrade_cap, ctx);
    init_state.initialized = true;
    event::emit(BulletinInitializedEvent {
        root_authority_did: bulletin.root_authority_did,
        meta_admins: meta_admins_for_event,
        admins: admins_for_event,
        admin_threshold,
        publisher,
        package_address,
    });
    transfer::share_object(bulletin);
    transfer::transfer(upgrade_manager, publisher);
}

public fun create_proposal(
    bulletin: &mut Bulletin,
    committee_type: u8,
    action_type: u8,
    target_address: address,
    target_did: vector<u8>,
    subject_type: u8,
    authorized_domains: vector<vector<u8>>,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
    params_hash: vector<u8>,
    effective_from_ms: u64,
    subject_expiry_ms: u64,
    threshold_value: u64,
    clock_ref: &Clock,
    ctx: &TxContext,
) {
    let sender = tx_context::sender(ctx);
    let expected_committee = expected_committee_for_action(action_type);
    assert!(committee_type == expected_committee, E_INVALID_COMMITTEE);
    assert_is_active_member(bulletin, committee_type, sender);
    validate_action_subject(action_type, subject_type);
    let now_ms = clock::timestamp_ms(clock_ref);
    validate_proposal_inputs(
        action_type,
        subject_type,
        &target_did,
        &authorized_domains,
        &policy_hash,
        &metadata_hash,
        &params_hash,
        effective_from_ms,
        subject_expiry_ms,
        now_ms,
    );

    touch_clock(bulletin, now_ms);
    prune_finalized_proposals_if_needed(&mut bulletin.proposals);
    assert!(count_pending_proposals(&bulletin.proposals) < MAX_PENDING_PROPOSAL_RECORDS, E_TOO_MANY_PENDING_PROPOSALS);
    if (action_type == ACTION_ADMIN_THRESHOLD_UPDATE) {
        validate_admin_threshold(threshold_value, count_active_members(&bulletin.admins));
    };

    let proposal = Proposal {
        proposal_id: bulletin.next_proposal_id,
        committee_type,
        action_type,
        subject_type,
        target_address,
        target_did,
        authorized_domains,
        policy_hash,
        metadata_hash,
        params_hash,
        created_by: sender,
        created_at_ms: now_ms,
        expires_at_ms: now_ms + MAX_VOTING_WINDOW_MS,
        effective_from_ms,
        subject_expiry_ms,
        threshold_value,
        required_approvals: current_threshold_for_new_proposal(bulletin, committee_type),
        status: PROPOSAL_PENDING,
        approvals: 0,
        rejections: 0,
        approval_voters: vector[],
        rejection_voters: vector[],
        finalized_at_ms: 0,
    };
    bulletin.next_proposal_id = bulletin.next_proposal_id + 1;
    vector::push_back(&mut bulletin.proposals, proposal);
}

public fun vote(
    bulletin: &mut Bulletin,
    proposal_id: u64,
    approve: bool,
    clock_ref: &Clock,
    ctx: &TxContext,
) {
    let sender = tx_context::sender(ctx);
    let committee_type = borrow_proposal(&bulletin.proposals, proposal_id).committee_type;
    let now_ms = clock::timestamp_ms(clock_ref);
    touch_clock(bulletin, now_ms);
    assert_is_active_member(bulletin, committee_type, sender);

    let proposal_ref = borrow_proposal_mut(&mut bulletin.proposals, proposal_id);
    assert!(proposal_ref.status == PROPOSAL_PENDING, E_PROPOSAL_NOT_PENDING);
    assert!(now_ms <= proposal_ref.expires_at_ms, E_PROPOSAL_EXPIRED);
    assert!(
        !has_address(&proposal_ref.approval_voters, sender) &&
            !has_address(&proposal_ref.rejection_voters, sender),
        E_DUPLICATE_VOTE
    );

    if (approve) {
        vector::push_back(&mut proposal_ref.approval_voters, sender);
        proposal_ref.approvals = proposal_ref.approvals + 1;
    } else {
        vector::push_back(&mut proposal_ref.rejection_voters, sender);
        proposal_ref.rejections = proposal_ref.rejections + 1;
    };
}

public fun refresh_proposal_status(
    bulletin: &mut Bulletin,
    proposal_id: u64,
    clock_ref: &Clock,
) {
    let now_ms = clock::timestamp_ms(clock_ref);
    touch_clock(bulletin, now_ms);

    let proposal_index = find_proposal_index(&bulletin.proposals, proposal_id);
    let proposal = *vector::borrow(&bulletin.proposals, proposal_index);
    assert!(proposal.status == PROPOSAL_PENDING, E_PROPOSAL_NOT_PENDING);

    let required_votes = proposal.required_approvals;
    if (proposal.approvals >= required_votes) {
        if (!can_apply_passed_proposal(bulletin, &proposal)) {
            let proposal_ref = vector::borrow_mut(&mut bulletin.proposals, proposal_index);
            proposal_ref.status = PROPOSAL_REJECTED_STATUS;
            proposal_ref.finalized_at_ms = now_ms;
            return
        };
        {
            let proposal_ref = vector::borrow_mut(&mut bulletin.proposals, proposal_index);
            proposal_ref.status = PROPOSAL_PASSED;
            proposal_ref.finalized_at_ms = now_ms;
        };
        apply_passed_proposal(bulletin, proposal, now_ms);
    } else if (now_ms > proposal.expires_at_ms) {
        let proposal_ref = vector::borrow_mut(&mut bulletin.proposals, proposal_index);
        proposal_ref.status = PROPOSAL_EXPIRED_STATUS;
        proposal_ref.finalized_at_ms = now_ms;
    };
}

public fun admin_threshold(bulletin: &Bulletin): u64 {
    bulletin.admin_threshold
}

public fun latest_event_sequence(bulletin: &Bulletin): u64 {
    bulletin.next_event_sequence
}

public fun root_authority_did(bulletin: &Bulletin): vector<u8> {
    bulletin.root_authority_did
}

public fun upgrade_publisher(manager: &UpgradeManager): address {
    manager.publisher
}

public fun upgrade_policy(manager: &UpgradeManager): u8 {
    manager.cap.policy()
}

public fun upgrade_version(manager: &UpgradeManager): u64 {
    package::version(&manager.cap)
}

public fun upgrade_package_id(manager: &UpgradeManager): object::ID {
    manager.cap.package()
}

public fun authorize_package_upgrade(
    manager: &mut UpgradeManager,
    policy: u8,
    digest: vector<u8>,
    ctx: &TxContext,
): package::UpgradeTicket {
    assert_package_publisher(manager, ctx);
    manager.cap.authorize(policy, digest)
}

public fun commit_package_upgrade(
    manager: &mut UpgradeManager,
    receipt: package::UpgradeReceipt,
    ctx: &TxContext,
) {
    assert_package_publisher(manager, ctx);
    manager.cap.commit(receipt);
}

public fun restrict_upgrade_policy_to_additive(
    manager: &mut UpgradeManager,
    ctx: &TxContext,
) {
    assert_package_publisher(manager, ctx);
    package::only_additive_upgrades(&mut manager.cap);
}

public fun restrict_upgrade_policy_to_dep_only(
    manager: &mut UpgradeManager,
    ctx: &TxContext,
) {
    assert_package_publisher(manager, ctx);
    package::only_dep_upgrades(&mut manager.cap);
}

#[test_only]
public fun latest_event_digest(bulletin: &Bulletin): vector<u8> {
    bulletin.last_event_digest
}

public fun active_meta_admin_count(bulletin: &Bulletin): u64 {
    count_active_members(&bulletin.meta_admins)
}

public fun active_admin_count(bulletin: &Bulletin): u64 {
    count_active_members(&bulletin.admins)
}

public fun meta_admin_count_total(bulletin: &Bulletin): u64 {
    vector::length(&bulletin.meta_admins)
}

public fun admin_count_total(bulletin: &Bulletin): u64 {
    vector::length(&bulletin.admins)
}

public fun meta_admin_at(bulletin: &Bulletin, index: u64): (address, u8) {
    let member = vector::borrow(&bulletin.meta_admins, index);
    (member.addr, member.status)
}

public fun admin_at(bulletin: &Bulletin, index: u64): (address, u8) {
    let member = vector::borrow(&bulletin.admins, index);
    (member.addr, member.status)
}

public fun proposal_status(bulletin: &Bulletin, proposal_id: u64): u8 {
    let proposal = borrow_proposal(&bulletin.proposals, proposal_id);
    proposal.status
}

public fun subject_status(bulletin: &Bulletin, subject_type: u8, subject_did: vector<u8>): u8 {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return SUBJECT_NONE
    };

    vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index)).status
}

public fun subject_version(bulletin: &Bulletin, subject_type: u8, subject_did: vector<u8>): u64 {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return 0
    };

    vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index)).version
}

public fun subject_domain_count(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
): u64 {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return 0
    };

    vector::length(&vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index)).authorized_domains)
}

public fun subject_exists(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
): bool {
    option::is_some(&find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did))
}

public fun subject_snapshot(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
): (bool, u8, u64, u64, u64) {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return (false, SUBJECT_NONE, 0, 0, 0)
    };

    let subject = vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index));
    (
        true,
        subject.status,
        subject.version,
        subject.effective_from_ms,
        subject.expires_at_ms,
    )
}

public fun subject_authorization_snapshot_at(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
    at_ms: u64,
): (bool, bool, u8, u64, u64, u64) {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return (false, false, SUBJECT_NONE, 0, 0, 0)
    };

    let subject = vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index));
    let is_authorized =
        subject.status == SUBJECT_ACTIVE &&
        (subject.effective_from_ms == 0 || subject.effective_from_ms <= at_ms) &&
        (subject.expires_at_ms == 0 || at_ms < subject.expires_at_ms);
    (
        true,
        is_authorized,
        subject.status,
        subject.version,
        subject.effective_from_ms,
        subject.expires_at_ms,
    )
}

public fun subject_is_authorized_at(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
    at_ms: u64,
): bool {
    let (_, is_authorized, _, _, _, _) =
        subject_authorization_snapshot_at(bulletin, subject_type, subject_did, at_ms);
    is_authorized
}

public fun subject_policy_hash(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
): vector<u8> {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return vector[]
    };

    vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index)).policy_hash
}

public fun subject_metadata_hash(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
): vector<u8> {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return vector[]
    };

    vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index)).metadata_hash
}

public fun subject_authorized_domains(
    bulletin: &Bulletin,
    subject_type: u8,
    subject_did: vector<u8>,
): vector<vector<u8>> {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, subject_type, &subject_did);
    if (option::is_none(&maybe_index)) {
        return vector[]
    };

    vector::borrow(&bulletin.subjects, option::destroy_some(maybe_index)).authorized_domains
}

public fun registrar_is_authorized_at(
    bulletin: &Bulletin,
    subject_did: vector<u8>,
    at_ms: u64,
): bool {
    subject_is_authorized_at(bulletin, SUBJECT_REGISTRAR, subject_did, at_ms)
}

public fun discovery_is_authorized_at(
    bulletin: &Bulletin,
    subject_did: vector<u8>,
    at_ms: u64,
): bool {
    subject_is_authorized_at(bulletin, SUBJECT_DISCOVERY, subject_did, at_ms)
}

public fun vc_issuer_is_authorized_at(
    bulletin: &Bulletin,
    subject_did: vector<u8>,
    at_ms: u64,
): bool {
    subject_is_authorized_at(bulletin, SUBJECT_VC_ISSUER, subject_did, at_ms)
}

public fun member_status(bulletin: &Bulletin, committee_type: u8, addr: address): u8 {
    if (committee_type == COMMITTEE_META_ADMIN) {
        let index = find_member_index(&bulletin.meta_admins, addr);
        let member = vector::borrow(&bulletin.meta_admins, index);
        member.status
    } else if (committee_type == COMMITTEE_ADMIN) {
        let index = find_member_index(&bulletin.admins, addr);
        let member = vector::borrow(&bulletin.admins, index);
        member.status
    } else {
        abort E_INVALID_COMMITTEE
    }
}

fun new_bulletin(
    root_authority_did: vector<u8>,
    meta_admins: vector<address>,
    admins: vector<address>,
    admin_threshold: u64,
    ctx: &mut TxContext,
): Bulletin {
    assert!(vector::length(&root_authority_did) > 0, E_EMPTY_SUBJECT_DID);
    assert!(vector::length(&root_authority_did) <= MAX_ROOT_AUTHORITY_DID_BYTES, E_INPUT_TOO_LARGE);
    assert!(vector::length(&meta_admins) >= MIN_ACTIVE_META_ADMINS, E_TOO_FEW_META_ADMINS);
    assert!(vector::length(&admins) >= MIN_ACTIVE_ADMINS, E_TOO_FEW_ADMINS);
    assert!(vector::length(&meta_admins) <= MAX_CONFIGURED_META_ADMINS, E_TOO_MANY_META_ADMINS);
    assert!(vector::length(&admins) <= MAX_CONFIGURED_ADMINS, E_TOO_MANY_ADMINS);
    validate_unique_addresses(&meta_admins);
    validate_unique_addresses(&admins);
    validate_admin_threshold(admin_threshold, vector::length(&admins));

    Bulletin {
        id: object::new(ctx),
        root_authority_did,
        meta_admins: members_from_addresses(meta_admins),
        admins: members_from_addresses(admins),
        admin_threshold,
        next_proposal_id: 1,
        next_event_sequence: 0,
        proposals: vector[],
        subjects: vector[],
        last_event_digest: vector[],
        last_clock_ms: 0,
    }
}

fun new_upgrade_manager(
    publisher: address,
    cap: package::UpgradeCap,
    ctx: &mut TxContext,
): UpgradeManager {
    UpgradeManager {
        id: object::new(ctx),
        publisher,
        cap,
    }
}

fun members_from_addresses(addresses: vector<address>): vector<Member> {
    let mut result = vector[];
    let count = vector::length(&addresses);
    let mut i = 0;
    while (i < count) {
        vector::push_back(
            &mut result,
            Member {
                addr: *vector::borrow(&addresses, i),
                status: MEMBER_ACTIVE,
            },
        );
        i = i + 1;
    };
    result
}

fun validate_proposal_inputs(
    action_type: u8,
    subject_type: u8,
    target_did: &vector<u8>,
    authorized_domains: &vector<vector<u8>>,
    policy_hash: &vector<u8>,
    metadata_hash: &vector<u8>,
    params_hash: &vector<u8>,
    effective_from_ms: u64,
    subject_expiry_ms: u64,
    now_ms: u64,
) {
    assert!(vector::length(metadata_hash) > 0, E_EMPTY_REQUIRED_HASH);
    assert!(vector::length(params_hash) > 0, E_EMPTY_REQUIRED_HASH);
    assert!(vector::length(policy_hash) <= MAX_HASH_BYTES, E_INPUT_TOO_LARGE);
    assert!(vector::length(metadata_hash) <= MAX_HASH_BYTES, E_INPUT_TOO_LARGE);
    assert!(vector::length(params_hash) <= MAX_HASH_BYTES, E_INPUT_TOO_LARGE);
    if (subject_type == SUBJECT_NONE) {
        assert!(vector::length(target_did) == 0, E_INVALID_SUBJECT_TYPE);
        assert!(vector::length(authorized_domains) == 0, E_INVALID_SUBJECT_TYPE);
        return
    };

    assert!(vector::length(target_did) > 0, E_EMPTY_SUBJECT_DID);
    assert!(vector::length(target_did) <= MAX_DID_BYTES, E_INPUT_TOO_LARGE);
    assert!(effective_from_ms == 0 || effective_from_ms <= now_ms, E_INVALID_SUBJECT_TIMING);
    assert!(subject_expiry_ms == 0 || subject_expiry_ms > now_ms, E_INVALID_SUBJECT_TIMING);
    assert!(subject_expiry_ms == 0 || effective_from_ms <= subject_expiry_ms, E_INVALID_SUBJECT_TIMING);

    if (subject_type == SUBJECT_REGISTRAR) {
        if (action_type == ACTION_REGISTRAR_AUTHORIZE || action_type == ACTION_REGISTRAR_DOMAINS_UPDATE) {
            validate_authorized_domains(authorized_domains);
        } else {
            assert!(vector::length(authorized_domains) == 0, E_INVALID_SUBJECT_TYPE);
        }
    } else if (subject_type == SUBJECT_DISCOVERY) {
        if (action_type == ACTION_DISCOVERY_AUTHORIZE || action_type == ACTION_DISCOVERY_DOMAINS_UPDATE) {
            validate_authorized_domains(authorized_domains);
        } else {
            assert!(vector::length(authorized_domains) == 0, E_INVALID_SUBJECT_TYPE);
        }
    } else {
        assert!(vector::length(authorized_domains) == 0, E_INVALID_SUBJECT_TYPE);
    }
}

fun validate_authorized_domains(authorized_domains: &vector<vector<u8>>) {
    let count = vector::length(authorized_domains);
    assert!(count > 0, E_EMPTY_AUTHORIZED_DOMAIN);
    assert!(count <= MAX_DOMAIN_COUNT, E_INPUT_TOO_LARGE);
    let mut i = 0;
    while (i < count) {
        let domain = vector::borrow(authorized_domains, i);
        assert!(vector::length(domain) > 0, E_EMPTY_AUTHORIZED_DOMAIN);
        assert!(vector::length(domain) <= MAX_DOMAIN_BYTES, E_INPUT_TOO_LARGE);
        assert!(is_canonical_authorized_domain(domain), E_NON_CANONICAL_AUTHORIZED_DOMAIN);
        if (is_wildcard_authorized_domain(domain)) {
            assert!(count == 1, E_WILDCARD_MIXED_AUTHORIZED_DOMAIN);
        };
        if (i > 0) {
            let previous = vector::borrow(authorized_domains, i - 1);
            assert!(compare_bytes(previous, domain) == 1, E_DUPLICATE_OR_UNSORTED_AUTHORIZED_DOMAIN);
        };
        i = i + 1;
    };
}

fun validate_unique_addresses(addresses: &vector<address>) {
    let count = vector::length(addresses);
    let mut i = 0;
    while (i < count) {
        let current = *vector::borrow(addresses, i);
        let mut j = i + 1;
        while (j < count) {
            assert!(current != *vector::borrow(addresses, j), E_DUPLICATE_MEMBER);
            j = j + 1;
        };
        i = i + 1;
    };
}

fun validate_action_subject(action_type: u8, subject_type: u8) {
    if (
        action_type == ACTION_META_ADD || action_type == ACTION_META_DISABLE ||
        action_type == ACTION_META_ENABLE || action_type == ACTION_META_REMOVE ||
        action_type == ACTION_ADMIN_ADD || action_type == ACTION_ADMIN_DISABLE ||
        action_type == ACTION_ADMIN_ENABLE || action_type == ACTION_ADMIN_REMOVE ||
        action_type == ACTION_ADMIN_THRESHOLD_UPDATE
    ) {
        assert!(subject_type == SUBJECT_NONE, E_INVALID_SUBJECT_TYPE);
    } else if (
        action_type == ACTION_REGISTRAR_AUTHORIZE || action_type == ACTION_REGISTRAR_SUSPEND ||
        action_type == ACTION_REGISTRAR_RECOVER || action_type == ACTION_REGISTRAR_REVOKE ||
        action_type == ACTION_REGISTRAR_DOMAINS_UPDATE
    ) {
        assert!(subject_type == SUBJECT_REGISTRAR, E_INVALID_SUBJECT_TYPE);
    } else if (
        action_type == ACTION_DISCOVERY_AUTHORIZE || action_type == ACTION_DISCOVERY_DOMAINS_UPDATE ||
        action_type == ACTION_DISCOVERY_SUSPEND || action_type == ACTION_DISCOVERY_RECOVER ||
        action_type == ACTION_DISCOVERY_REVOKE
    ) {
        assert!(subject_type == SUBJECT_DISCOVERY, E_INVALID_SUBJECT_TYPE);
    } else if (
        action_type == ACTION_VC_ISSUER_AUTHORIZE || action_type == ACTION_VC_ISSUER_SUSPEND ||
        action_type == ACTION_VC_ISSUER_RECOVER || action_type == ACTION_VC_ISSUER_REVOKE
    ) {
        assert!(subject_type == SUBJECT_VC_ISSUER, E_INVALID_SUBJECT_TYPE);
    } else {
        abort E_INVALID_ACTION
    }
}

fun expected_committee_for_action(action_type: u8): u8 {
    if (
        action_type == ACTION_META_ADD || action_type == ACTION_META_DISABLE ||
        action_type == ACTION_META_ENABLE || action_type == ACTION_META_REMOVE ||
        action_type == ACTION_ADMIN_ADD || action_type == ACTION_ADMIN_DISABLE ||
        action_type == ACTION_ADMIN_ENABLE || action_type == ACTION_ADMIN_REMOVE ||
        action_type == ACTION_ADMIN_THRESHOLD_UPDATE
    ) {
        COMMITTEE_META_ADMIN
    } else if (
        action_type == ACTION_REGISTRAR_AUTHORIZE || action_type == ACTION_REGISTRAR_SUSPEND ||
        action_type == ACTION_REGISTRAR_RECOVER || action_type == ACTION_REGISTRAR_REVOKE ||
        action_type == ACTION_REGISTRAR_DOMAINS_UPDATE ||
        action_type == ACTION_DISCOVERY_AUTHORIZE || action_type == ACTION_DISCOVERY_DOMAINS_UPDATE ||
        action_type == ACTION_DISCOVERY_SUSPEND || action_type == ACTION_DISCOVERY_RECOVER ||
        action_type == ACTION_DISCOVERY_REVOKE || action_type == ACTION_VC_ISSUER_AUTHORIZE ||
        action_type == ACTION_VC_ISSUER_SUSPEND || action_type == ACTION_VC_ISSUER_RECOVER ||
        action_type == ACTION_VC_ISSUER_REVOKE
    ) {
        COMMITTEE_ADMIN
    } else {
        abort E_INVALID_ACTION
    }
}

fun assert_is_active_member(bulletin: &Bulletin, committee_type: u8, addr: address) {
    let status = member_status(bulletin, committee_type, addr);
    assert!(status == MEMBER_ACTIVE, E_NOT_ACTIVE_MEMBER);
}

fun assert_package_publisher(manager: &UpgradeManager, ctx: &TxContext) {
    assert!(tx_context::sender(ctx) == manager.publisher, E_NOT_PACKAGE_PUBLISHER);
}

fun count_active_members(members: &vector<Member>): u64 {
    let count = vector::length(members);
    let mut active = 0;
    let mut i = 0;
    while (i < count) {
        if (vector::borrow(members, i).status == MEMBER_ACTIVE) {
            active = active + 1;
        };
        i = i + 1;
    };
    active
}

fun count_configured_members(members: &vector<Member>): u64 {
    let count = vector::length(members);
    let mut configured = 0;
    let mut i = 0;
    while (i < count) {
        if (vector::borrow(members, i).status != MEMBER_REMOVED) {
            configured = configured + 1;
        };
        i = i + 1;
    };
    configured
}

fun validate_admin_threshold(threshold: u64, active_admin_count: u64) {
    assert!(threshold >= 1, E_INVALID_THRESHOLD);
    assert!(threshold <= max_threshold(active_admin_count), E_INVALID_THRESHOLD);
}

fun max_threshold(active_count: u64): u64 {
    (active_count * 2) / 3 + 1
}

fun current_threshold_for_new_proposal(bulletin: &Bulletin, committee_type: u8): u64 {
    if (committee_type == COMMITTEE_META_ADMIN) {
        max_threshold(count_active_members(&bulletin.meta_admins))
    } else if (committee_type == COMMITTEE_ADMIN) {
        bulletin.admin_threshold
    } else {
        abort E_INVALID_COMMITTEE
    }
}

fun borrow_proposal(proposals: &vector<Proposal>, proposal_id: u64): &Proposal {
    let index = find_proposal_index(proposals, proposal_id);
    vector::borrow(proposals, index)
}

fun borrow_proposal_mut(proposals: &mut vector<Proposal>, proposal_id: u64): &mut Proposal {
    let index = find_proposal_index(proposals, proposal_id);
    vector::borrow_mut(proposals, index)
}

fun find_proposal_index(proposals: &vector<Proposal>, proposal_id: u64): u64 {
    let count = vector::length(proposals);
    let mut i = 0;
    while (i < count) {
        if (vector::borrow(proposals, i).proposal_id == proposal_id) {
            return i
        };
        i = i + 1;
    };
    abort E_PROPOSAL_NOT_FOUND
}

fun find_member_index(members: &vector<Member>, addr: address): u64 {
    let count = vector::length(members);
    let mut i = 0;
    while (i < count) {
        if (vector::borrow(members, i).addr == addr) {
            return i
        };
        i = i + 1;
    };
    abort E_MEMBER_NOT_FOUND
}

fun find_member_index_opt(members: &vector<Member>, addr: address): option::Option<u64> {
    let count = vector::length(members);
    let mut i = 0;
    while (i < count) {
        if (vector::borrow(members, i).addr == addr) {
            return option::some(i)
        };
        i = i + 1;
    };
    option::none()
}

fun find_subject_index(subjects: &vector<SubjectState>, subject_type: u8, subject_did: &vector<u8>): u64 {
    let count = vector::length(subjects);
    let mut i = 0;
    while (i < count) {
        let subject = vector::borrow(subjects, i);
        if (subject.subject_type == subject_type && &subject.subject_did == subject_did) {
            return i
        };
        i = i + 1;
    };
    abort E_SUBJECT_NOT_FOUND
}

fun has_address(addresses: &vector<address>, addr: address): bool {
    let count = vector::length(addresses);
    let mut i = 0;
    while (i < count) {
        if (*vector::borrow(addresses, i) == addr) {
            return true
        };
        i = i + 1;
    };
    false
}

fun touch_clock(bulletin: &mut Bulletin, now_ms: u64) {
    assert!(now_ms >= bulletin.last_clock_ms, E_CLOCK_REGRESSION);
    bulletin.last_clock_ms = now_ms;
}

fun count_pending_proposals(proposals: &vector<Proposal>): u64 {
    let mut i = 0;
    let mut pending = 0;
    while (i < vector::length(proposals)) {
        if (vector::borrow(proposals, i).status == PROPOSAL_PENDING) {
            pending = pending + 1;
        };
        i = i + 1;
    };
    pending
}

fun prune_finalized_proposals_if_needed(proposals: &mut vector<Proposal>) {
    while (vector::length(proposals) >= MAX_TOTAL_PROPOSAL_RECORDS) {
        let maybe_index = find_oldest_finalized_proposal_index(proposals);
        if (option::is_none(&maybe_index)) {
            return
        };
        vector::remove(proposals, option::destroy_some(maybe_index));
    };
}

fun find_oldest_finalized_proposal_index(proposals: &vector<Proposal>): option::Option<u64> {
    let count = vector::length(proposals);
    let mut i = 0;
    let mut found = false;
    let mut oldest_index = 0;
    let mut oldest_id = 0;
    while (i < count) {
        let proposal = vector::borrow(proposals, i);
        if (proposal.status != PROPOSAL_PENDING) {
            if (!found || proposal.proposal_id < oldest_id) {
                found = true;
                oldest_index = i;
                oldest_id = proposal.proposal_id;
            };
        };
        i = i + 1;
    };
    if (found) option::some(oldest_index) else option::none()
}

fun can_apply_passed_proposal(bulletin: &Bulletin, proposal: &Proposal): bool {
    if (proposal.action_type == ACTION_META_ADD) {
        option::is_none(&find_member_index_opt(&bulletin.meta_admins, proposal.target_address)) &&
            count_configured_members(&bulletin.meta_admins) < MAX_CONFIGURED_META_ADMINS
    } else if (proposal.action_type == ACTION_META_DISABLE || proposal.action_type == ACTION_META_REMOVE) {
        can_transition_member_status(&bulletin.meta_admins, proposal.target_address, MIN_ACTIVE_META_ADMINS, MEMBER_ACTIVE)
    } else if (proposal.action_type == ACTION_META_ENABLE) {
        has_member_status(&bulletin.meta_admins, proposal.target_address, MEMBER_DISABLED)
    } else if (proposal.action_type == ACTION_ADMIN_ADD) {
        option::is_none(&find_member_index_opt(&bulletin.admins, proposal.target_address)) &&
            count_configured_members(&bulletin.admins) < MAX_CONFIGURED_ADMINS
    } else if (proposal.action_type == ACTION_ADMIN_DISABLE || proposal.action_type == ACTION_ADMIN_REMOVE) {
        can_transition_member_status(&bulletin.admins, proposal.target_address, MIN_ACTIVE_ADMINS, MEMBER_ACTIVE)
    } else if (proposal.action_type == ACTION_ADMIN_ENABLE) {
        has_member_status(&bulletin.admins, proposal.target_address, MEMBER_DISABLED)
    } else if (proposal.action_type == ACTION_ADMIN_THRESHOLD_UPDATE) {
        proposal.threshold_value >= 1 &&
            proposal.threshold_value <= max_threshold(count_active_members(&bulletin.admins))
    } else {
        can_apply_subject_proposal(bulletin, proposal)
    }
}

fun can_transition_member_status(
    members: &vector<Member>,
    addr: address,
    minimum_active: u64,
    expected_status: u8,
): bool {
    let maybe_index = find_member_index_opt(members, addr);
    if (option::is_none(&maybe_index)) {
        return false
    };
    let member = vector::borrow(members, option::destroy_some(maybe_index));
    if (member.status != expected_status) {
        return false
    };
    count_active_members(members) > minimum_active
}

fun has_member_status(members: &vector<Member>, addr: address, expected_status: u8): bool {
    let maybe_index = find_member_index_opt(members, addr);
    if (option::is_none(&maybe_index)) {
        return false
    };
    vector::borrow(members, option::destroy_some(maybe_index)).status == expected_status
}

fun subject_has_status(
    subjects: &vector<SubjectState>,
    subject_type: u8,
    subject_did: &vector<u8>,
    expected_status: u8,
): bool {
    let maybe_index = find_subject_index_opt(subjects, subject_type, subject_did);
    if (option::is_none(&maybe_index)) {
        return false
    };
    vector::borrow(subjects, option::destroy_some(maybe_index)).status == expected_status
}

fun subject_is_active_or_suspended(
    subjects: &vector<SubjectState>,
    subject_type: u8,
    subject_did: &vector<u8>,
): bool {
    let maybe_index = find_subject_index_opt(subjects, subject_type, subject_did);
    if (option::is_none(&maybe_index)) {
        return false
    };
    let status = vector::borrow(subjects, option::destroy_some(maybe_index)).status;
    status == SUBJECT_ACTIVE || status == SUBJECT_SUSPENDED
}

fun can_apply_subject_proposal(bulletin: &Bulletin, proposal: &Proposal): bool {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, proposal.subject_type, &proposal.target_did);
    if (
        proposal.action_type == ACTION_REGISTRAR_AUTHORIZE ||
        proposal.action_type == ACTION_DISCOVERY_AUTHORIZE ||
        proposal.action_type == ACTION_VC_ISSUER_AUTHORIZE
    ) {
        option::is_none(&maybe_index)
    } else if (proposal.action_type == ACTION_REGISTRAR_DOMAINS_UPDATE) {
        subject_has_status(&bulletin.subjects, proposal.subject_type, &proposal.target_did, SUBJECT_ACTIVE)
    } else if (proposal.action_type == ACTION_DISCOVERY_DOMAINS_UPDATE) {
        subject_has_status(&bulletin.subjects, proposal.subject_type, &proposal.target_did, SUBJECT_ACTIVE)
    } else if (
        proposal.action_type == ACTION_REGISTRAR_SUSPEND || proposal.action_type == ACTION_DISCOVERY_SUSPEND ||
        proposal.action_type == ACTION_VC_ISSUER_SUSPEND
    ) {
        subject_has_status(&bulletin.subjects, proposal.subject_type, &proposal.target_did, SUBJECT_ACTIVE)
    } else if (
        proposal.action_type == ACTION_REGISTRAR_RECOVER || proposal.action_type == ACTION_DISCOVERY_RECOVER ||
        proposal.action_type == ACTION_VC_ISSUER_RECOVER
    ) {
        subject_has_status(&bulletin.subjects, proposal.subject_type, &proposal.target_did, SUBJECT_SUSPENDED)
    } else if (
        proposal.action_type == ACTION_REGISTRAR_REVOKE ||
        proposal.action_type == ACTION_DISCOVERY_REVOKE ||
        proposal.action_type == ACTION_VC_ISSUER_REVOKE
    ) {
        subject_is_active_or_suspended(&bulletin.subjects, proposal.subject_type, &proposal.target_did)
    } else {
        false
    }
}

fun apply_passed_proposal(bulletin: &mut Bulletin, proposal: Proposal, now_ms: u64) {
    if (proposal.action_type == ACTION_META_ADD) {
        add_member(
            &mut bulletin.meta_admins,
            proposal.target_address,
            MAX_CONFIGURED_META_ADMINS,
            E_TOO_MANY_META_ADMINS,
        );
    } else if (proposal.action_type == ACTION_META_DISABLE) {
        update_member_status(&mut bulletin.meta_admins, proposal.target_address, MEMBER_DISABLED, MIN_ACTIVE_META_ADMINS);
    } else if (proposal.action_type == ACTION_META_ENABLE) {
        enable_member(&mut bulletin.meta_admins, proposal.target_address);
    } else if (proposal.action_type == ACTION_META_REMOVE) {
        update_member_status(&mut bulletin.meta_admins, proposal.target_address, MEMBER_REMOVED, MIN_ACTIVE_META_ADMINS);
    } else if (proposal.action_type == ACTION_ADMIN_ADD) {
        add_member(
            &mut bulletin.admins,
            proposal.target_address,
            MAX_CONFIGURED_ADMINS,
            E_TOO_MANY_ADMINS,
        );
    } else if (proposal.action_type == ACTION_ADMIN_DISABLE) {
        update_member_status(&mut bulletin.admins, proposal.target_address, MEMBER_DISABLED, MIN_ACTIVE_ADMINS);
    } else if (proposal.action_type == ACTION_ADMIN_ENABLE) {
        enable_member(&mut bulletin.admins, proposal.target_address);
    } else if (proposal.action_type == ACTION_ADMIN_REMOVE) {
        update_member_status(&mut bulletin.admins, proposal.target_address, MEMBER_REMOVED, MIN_ACTIVE_ADMINS);
    } else if (proposal.action_type == ACTION_ADMIN_THRESHOLD_UPDATE) {
        validate_admin_threshold(proposal.threshold_value, count_active_members(&bulletin.admins));
        bulletin.admin_threshold = proposal.threshold_value;
    } else {
        apply_subject_proposal(bulletin, &proposal, now_ms);
    };
    emit_execution_event(bulletin, &proposal, now_ms);
}

fun add_member(
    members: &mut vector<Member>,
    addr: address,
    max_members: u64,
    too_many_error: u64,
) {
    let count = vector::length(members);
    let mut i = 0;
    while (i < count) {
        let member = vector::borrow(members, i);
        assert!(member.addr != addr, E_DUPLICATE_MEMBER);
        i = i + 1;
    };
    assert!(count_configured_members(members) < max_members, too_many_error);
    vector::push_back(
        members,
        Member {
            addr,
            status: MEMBER_ACTIVE,
        },
    );
}

fun update_member_status(
    members: &mut vector<Member>,
    addr: address,
    next_status: u8,
    minimum_active: u64,
) {
    let index = find_member_index(members, addr);
    let current_status = vector::borrow(members, index).status;
    assert!(current_status == MEMBER_ACTIVE, E_MEMBER_STATUS);
    let active_after = count_active_members(members) - 1;
    assert!(active_after >= minimum_active, E_BELOW_MIN_ACTIVE);
    vector::borrow_mut(members, index).status = next_status;
}

fun enable_member(members: &mut vector<Member>, addr: address) {
    let index = find_member_index(members, addr);
    let current_status = vector::borrow(members, index).status;
    assert!(current_status == MEMBER_DISABLED, E_MEMBER_STATUS);
    vector::borrow_mut(members, index).status = MEMBER_ACTIVE;
}

fun apply_subject_proposal(bulletin: &mut Bulletin, proposal: &Proposal, now_ms: u64) {
    let maybe_index = find_subject_index_opt(&bulletin.subjects, proposal.subject_type, &proposal.target_did);
    if (proposal.action_type == ACTION_REGISTRAR_AUTHORIZE || proposal.action_type == ACTION_DISCOVERY_AUTHORIZE || proposal.action_type == ACTION_VC_ISSUER_AUTHORIZE) {
        option::destroy_none(maybe_index);
        upsert_subject(
            &mut bulletin.subjects,
            option::none(),
            proposal.subject_type,
            proposal.target_did,
            SUBJECT_ACTIVE,
            proposal.authorized_domains,
            proposal.policy_hash,
            proposal.metadata_hash,
            proposal.effective_from_ms,
            proposal.subject_expiry_ms,
            now_ms,
        );
    } else if (proposal.action_type == ACTION_REGISTRAR_DOMAINS_UPDATE || proposal.action_type == ACTION_DISCOVERY_DOMAINS_UPDATE) {
        let index = option::destroy_some(maybe_index);
        let subject_ref = vector::borrow_mut(&mut bulletin.subjects, index);
        assert!(subject_ref.status == SUBJECT_ACTIVE, E_INVALID_SUBJECT_STATE);
        subject_ref.authorized_domains = proposal.authorized_domains;
        subject_ref.policy_hash = proposal.policy_hash;
        subject_ref.metadata_hash = proposal.metadata_hash;
        subject_ref.version = subject_ref.version + 1;
        subject_ref.updated_at_ms = now_ms;
    } else if (
        proposal.action_type == ACTION_REGISTRAR_SUSPEND || proposal.action_type == ACTION_DISCOVERY_SUSPEND ||
        proposal.action_type == ACTION_VC_ISSUER_SUSPEND
    ) {
        transition_subject(&mut bulletin.subjects, maybe_index, SUBJECT_ACTIVE, SUBJECT_SUSPENDED, now_ms, proposal.policy_hash, proposal.metadata_hash);
    } else if (
        proposal.action_type == ACTION_REGISTRAR_RECOVER || proposal.action_type == ACTION_DISCOVERY_RECOVER ||
        proposal.action_type == ACTION_VC_ISSUER_RECOVER
    ) {
        transition_subject(&mut bulletin.subjects, maybe_index, SUBJECT_SUSPENDED, SUBJECT_ACTIVE, now_ms, proposal.policy_hash, proposal.metadata_hash);
    } else if (
        proposal.action_type == ACTION_REGISTRAR_REVOKE || proposal.action_type == ACTION_DISCOVERY_REVOKE ||
        proposal.action_type == ACTION_VC_ISSUER_REVOKE
    ) {
        revoke_subject(&mut bulletin.subjects, maybe_index, now_ms, proposal.policy_hash, proposal.metadata_hash);
    } else {
        abort E_INVALID_ACTION
    };
}

fun find_subject_index_opt(
    subjects: &vector<SubjectState>,
    subject_type: u8,
    subject_did: &vector<u8>,
): option::Option<u64> {
    let count = vector::length(subjects);
    let mut i = 0;
    while (i < count) {
        let subject = vector::borrow(subjects, i);
        if (subject.subject_type == subject_type && &subject.subject_did == subject_did) {
            return option::some(i)
        };
        i = i + 1;
    };
    option::none()
}

fun is_canonical_authorized_domain(domain: &vector<u8>): bool {
    let mut i = 0;
    while (i < vector::length(domain)) {
        let byte = *vector::borrow(domain, i);
        if (byte >= 65 && byte <= 90) {
            return false
        };
        i = i + 1;
    };
    true
}

fun is_wildcard_authorized_domain(domain: &vector<u8>): bool {
    vector::length(domain) == 1 && *vector::borrow(domain, 0) == 42
}

fun compare_bytes(left: &vector<u8>, right: &vector<u8>): u8 {
    let left_len = vector::length(left);
    let right_len = vector::length(right);
    let mut i = 0;
    let min_len = if (left_len < right_len) left_len else right_len;
    while (i < min_len) {
        let left_byte = *vector::borrow(left, i);
        let right_byte = *vector::borrow(right, i);
        if (left_byte < right_byte) {
            return 1
        };
        if (left_byte > right_byte) {
            return 2
        };
        i = i + 1;
    };
    if (left_len < right_len) {
        1
    } else if (left_len > right_len) {
        2
    } else {
        0
    }
}

fun upsert_subject(
    subjects: &mut vector<SubjectState>,
    maybe_index: option::Option<u64>,
    subject_type: u8,
    subject_did: vector<u8>,
    status: u8,
    authorized_domains: vector<vector<u8>>,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
    effective_from_ms: u64,
    expires_at_ms: u64,
    now_ms: u64,
) {
    if (option::is_some(&maybe_index)) {
        let index = option::destroy_some(maybe_index);
        let subject_ref = vector::borrow_mut(subjects, index);
        subject_ref.status = status;
        subject_ref.authorized_domains = authorized_domains;
        subject_ref.policy_hash = policy_hash;
        subject_ref.metadata_hash = metadata_hash;
        subject_ref.effective_from_ms = effective_from_ms;
        subject_ref.expires_at_ms = expires_at_ms;
        subject_ref.version = subject_ref.version + 1;
        subject_ref.updated_at_ms = now_ms;
    } else {
        option::destroy_none(maybe_index);
        vector::push_back(
            subjects,
            SubjectState {
                subject_did,
                subject_type,
                status,
                authorized_domains,
                policy_hash,
                metadata_hash,
                effective_from_ms,
                expires_at_ms,
                version: 1,
                updated_at_ms: now_ms,
            },
        );
    };
}

fun transition_subject(
    subjects: &mut vector<SubjectState>,
    maybe_index: option::Option<u64>,
    from_status: u8,
    to_status: u8,
    now_ms: u64,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
) {
    let index = option::destroy_some(maybe_index);
    let subject_ref = vector::borrow_mut(subjects, index);
    assert!(subject_ref.status == from_status, E_INVALID_SUBJECT_STATE);
    subject_ref.status = to_status;
    subject_ref.policy_hash = policy_hash;
    subject_ref.metadata_hash = metadata_hash;
    subject_ref.version = subject_ref.version + 1;
    subject_ref.updated_at_ms = now_ms;
}

fun revoke_subject(
    subjects: &mut vector<SubjectState>,
    maybe_index: option::Option<u64>,
    now_ms: u64,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
) {
    let index = option::destroy_some(maybe_index);
    let subject_ref = vector::borrow_mut(subjects, index);
    assert!(
        subject_ref.status == SUBJECT_ACTIVE || subject_ref.status == SUBJECT_SUSPENDED,
        E_INVALID_SUBJECT_STATE
    );
    subject_ref.status = SUBJECT_REVOKED;
    subject_ref.policy_hash = policy_hash;
    subject_ref.metadata_hash = metadata_hash;
    subject_ref.version = subject_ref.version + 1;
    subject_ref.updated_at_ms = now_ms;
}

fun emit_execution_event(bulletin: &mut Bulletin, proposal: &Proposal, now_ms: u64) {
    let (subject_status, domains, effective_from_ms, expires_at_ms, policy_hash, metadata_hash) =
        execution_subject_snapshot(bulletin, proposal);

    let next_sequence = bulletin.next_event_sequence + 1;
    let previous_digest = bulletin.last_event_digest;
    let event_digest = compute_event_digest(
        next_sequence,
        bulletin.root_authority_did,
        proposal.action_type,
        proposal.proposal_id,
        proposal.committee_type,
        proposal.target_address,
        proposal.subject_type,
        proposal.target_did,
        subject_status,
        domains,
        effective_from_ms,
        expires_at_ms,
        policy_hash,
        metadata_hash,
        previous_digest,
        now_ms,
    );

    event::emit(GovernanceExecutionEvent {
        event_type: proposal.action_type,
        sequence: next_sequence,
        root_authority_did: bulletin.root_authority_did,
        proposal_id: proposal.proposal_id,
        committee_type: proposal.committee_type,
        target_address: proposal.target_address,
        subject_did: proposal.target_did,
        subject_type: proposal.subject_type,
        subject_status,
        authorized_domains: domains,
        effective_from_ms,
        expires_at_ms,
        policy_hash,
        metadata_hash,
        previous_event_digest: previous_digest,
        event_digest,
        emitted_at_ms: now_ms,
    });

    bulletin.next_event_sequence = next_sequence;
    bulletin.last_event_digest = event_digest;
}

fun execution_subject_snapshot(
    bulletin: &Bulletin,
    proposal: &Proposal,
): (u8, vector<vector<u8>>, u64, u64, vector<u8>, vector<u8>) {
    if (proposal.subject_type == SUBJECT_NONE) {
        (
            SUBJECT_NONE,
            vector[],
            0,
            0,
            proposal.policy_hash,
            proposal.metadata_hash,
        )
    } else {
        let subject = vector::borrow(
            &bulletin.subjects,
            find_subject_index(&bulletin.subjects, proposal.subject_type, &proposal.target_did),
        );
        (
            subject.status,
            subject.authorized_domains,
            subject.effective_from_ms,
            subject.expires_at_ms,
            subject.policy_hash,
            subject.metadata_hash,
        )
    }
}

fun compute_event_digest(
    sequence: u64,
    root_authority_did: vector<u8>,
    action_type: u8,
    proposal_id: u64,
    committee_type: u8,
    target_address: address,
    subject_type: u8,
    subject_did: vector<u8>,
    subject_status: u8,
    authorized_domains: vector<vector<u8>>,
    effective_from_ms: u64,
    expires_at_ms: u64,
    policy_hash: vector<u8>,
    metadata_hash: vector<u8>,
    previous_digest: vector<u8>,
    emitted_at_ms: u64,
): vector<u8> {
    let mut payload = bcs::to_bytes(&sequence);
    vector::append(&mut payload, root_authority_did);
    vector::append(&mut payload, bcs::to_bytes(&action_type));
    vector::append(&mut payload, bcs::to_bytes(&proposal_id));
    vector::append(&mut payload, bcs::to_bytes(&committee_type));
    vector::append(&mut payload, bcs::to_bytes(&target_address));
    vector::append(&mut payload, bcs::to_bytes(&subject_type));
    vector::append(&mut payload, subject_did);
    vector::append(&mut payload, bcs::to_bytes(&subject_status));
    vector::append(&mut payload, bcs::to_bytes(&authorized_domains));
    vector::append(&mut payload, bcs::to_bytes(&effective_from_ms));
    vector::append(&mut payload, bcs::to_bytes(&expires_at_ms));
    vector::append(&mut payload, policy_hash);
    vector::append(&mut payload, metadata_hash);
    vector::append(&mut payload, previous_digest);
    vector::append(&mut payload, bcs::to_bytes(&emitted_at_ms));
    hash::sha3_256(payload)
}
