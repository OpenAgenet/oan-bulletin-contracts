// Copyright (c) 2026 OpenAgenet contributors
//
// Initial author: JINLIANG XU
// Email: jlxufly@gmail.com

#[test_only]
module oan_bulletin::bulletin_tests;

use oan_bulletin::bulletin;
use std::bcs;
use std::hash;
use std::vector;
use sui::clock::{Self as clock, Clock};
use sui::object;
use sui::package;
use sui::test_scenario::{Self as ts};
use sui::transfer;

const META1: address = @0x100;
const META2: address = @0x101;
const META3: address = @0x102;
const META4: address = @0x103;
const META5: address = @0x104;
const META6: address = @0x105;
const META7: address = @0x106;
const META8: address = @0x107;
const META9: address = @0x108;
const META10: address = @0x109;
const META11: address = @0x10A;
const META12: address = @0x10B;
const META13: address = @0x10C;
const META14: address = @0x10D;
const META15: address = @0x10E;
const META16: address = @0x10F;
const ADMIN1: address = @0x200;
const ADMIN2: address = @0x201;
const ADMIN3: address = @0x202;
const ADMIN4: address = @0x203;
const ADMIN5: address = @0x204;
const ADMIN6: address = @0x205;
const ADMIN7: address = @0x206;
const ADMIN8: address = @0x207;
const ADMIN9: address = @0x208;
const ADMIN10: address = @0x209;
const ADMIN11: address = @0x20A;
const ADMIN12: address = @0x20B;
const ADMIN13: address = @0x20C;
const ADMIN14: address = @0x20D;
const ADMIN15: address = @0x20E;
const ADMIN16: address = @0x20F;
const ADMIN17: address = @0x210;
const ADMIN18: address = @0x211;
const ADMIN19: address = @0x212;
const ADMIN20: address = @0x213;
const ADMIN21: address = @0x214;
const ADMIN22: address = @0x215;
const ADMIN23: address = @0x216;
const ADMIN24: address = @0x217;
const ADMIN25: address = @0x218;
const ADMIN26: address = @0x219;

const ROOT_AUTHORITY_DID: vector<u8> = b"did:web:root.example.org";
const REGISTRAR_DID: vector<u8> = b"did:ans:registrar:official";
const DISCOVERY_DID: vector<u8> = b"did:ans:discovery:official";
const VC_ISSUER_DID: vector<u8> = b"did:ans:vc-issuer:official";

const COMMITTEE_META_ADMIN: u8 = 1;
const COMMITTEE_ADMIN: u8 = 2;
const SUBJECT_NONE: u8 = 0;
const SUBJECT_REGISTRAR: u8 = 1;
const SUBJECT_DISCOVERY: u8 = 2;
const SUBJECT_VC_ISSUER: u8 = 3;
const MEMBER_ACTIVE: u8 = 1;
const MEMBER_DISABLED: u8 = 2;
const MEMBER_REMOVED: u8 = 3;
const STATUS_ACTIVE: u8 = 1;
const STATUS_SUSPENDED: u8 = 2;
const STATUS_REVOKED: u8 = 3;
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
const PROPOSAL_REJECTED: u8 = 4;
const TEST_PACKAGE_ID: address = @0xB001;

fun bootstrap() {
    let mut scenario = ts::begin(META1);
    {
        let clock_obj = clock::create_for_testing(scenario.ctx());
        clock::share_for_testing(clock_obj);
        bulletin::init_for_testing(scenario.ctx());
        ts::next_tx(&mut scenario, META1);
        let mut init_state = ts::take_shared<bulletin::BulletinInitState>(&scenario);
        bulletin::override_init_package_address_for_testing(&mut init_state, TEST_PACKAGE_ID);
        let upgrade_cap = package::test_publish(object::id_from_address(TEST_PACKAGE_ID), scenario.ctx());
        bulletin::initialize(
            &mut init_state,
            ROOT_AUTHORITY_DID,
            vector[META1, META2, META3, META4],
            vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4],
            2,
            upgrade_cap,
            scenario.ctx(),
        );
        ts::return_shared(init_state);
    };
    scenario.end();
}

fun bootstrap_with_committees(
    meta_admins: vector<address>,
    admins: vector<address>,
    admin_threshold: u64,
) {
    let mut scenario = ts::begin(*vector::borrow(&meta_admins, 0));
    {
        let clock_obj = clock::create_for_testing(scenario.ctx());
        clock::share_for_testing(clock_obj);
        bulletin::init_for_testing(scenario.ctx());
        ts::next_tx(&mut scenario, *vector::borrow(&meta_admins, 0));
        let mut init_state = ts::take_shared<bulletin::BulletinInitState>(&scenario);
        bulletin::override_init_package_address_for_testing(&mut init_state, TEST_PACKAGE_ID);
        let upgrade_cap = package::test_publish(object::id_from_address(TEST_PACKAGE_ID), scenario.ctx());
        bulletin::initialize(
            &mut init_state,
            ROOT_AUTHORITY_DID,
            meta_admins,
            admins,
            admin_threshold,
            upgrade_cap,
            scenario.ctx(),
        );
        ts::return_shared(init_state);
    };
    scenario.end();
}

fun advance_clock(scenario: &ts::Scenario, delta_ms: u64): Clock {
    let mut clock_ref = ts::take_shared<Clock>(scenario);
    clock::increment_for_testing(&mut clock_ref, delta_ms);
    clock_ref
}

fun create_meta_add_admin5_proposal(scenario: &mut ts::Scenario) {
    let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(scenario);
    let clock_ref = ts::take_shared<Clock>(scenario);
    bulletin::create_proposal(
        &mut bulletin_obj,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_ADD,
        ADMIN5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy",
        b"meta-admin-add",
        b"params-add-admin5",
        0,
        0,
        0,
        &clock_ref,
        scenario.ctx(),
    );
    ts::return_shared(clock_ref);
    ts::return_shared(bulletin_obj);
}

fun create_proposal_with_signer(
    scenario: &mut ts::Scenario,
    signer: address,
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
) {
    ts::next_tx(scenario, signer);
    let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(scenario);
    let clock_ref = ts::take_shared<Clock>(scenario);
    bulletin::create_proposal(
        &mut bulletin_obj,
        committee_type,
        action_type,
        target_address,
        target_did,
        subject_type,
        authorized_domains,
        policy_hash,
        metadata_hash,
        params_hash,
        effective_from_ms,
        subject_expiry_ms,
        threshold_value,
        &clock_ref,
        scenario.ctx(),
    );
    ts::return_shared(clock_ref);
    ts::return_shared(bulletin_obj);
}

fun vote_with_signer(
    scenario: &mut ts::Scenario,
    signer: address,
    proposal_id: u64,
    approve: bool,
) {
    ts::next_tx(scenario, signer);
    let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(scenario);
    let clock_ref = ts::take_shared<Clock>(scenario);
    bulletin::vote(&mut bulletin_obj, proposal_id, approve, &clock_ref, scenario.ctx());
    ts::return_shared(clock_ref);
    ts::return_shared(bulletin_obj);
}

fun refresh_with_signer(scenario: &mut ts::Scenario, signer: address, proposal_id: u64) {
    ts::next_tx(scenario, signer);
    let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(scenario);
    let clock_ref = ts::take_shared<Clock>(scenario);
    bulletin::refresh_proposal_status(&mut bulletin_obj, proposal_id, &clock_ref);
    ts::return_shared(clock_ref);
    ts::return_shared(bulletin_obj);
}

fun pass_admin_proposal(scenario: &mut ts::Scenario, proposal_id: u64) {
    vote_with_signer(scenario, ADMIN1, proposal_id, true);
    vote_with_signer(scenario, ADMIN2, proposal_id, true);
    refresh_with_signer(scenario, ADMIN2, proposal_id);
}

fun pass_meta_proposal(scenario: &mut ts::Scenario, proposal_id: u64) {
    vote_with_signer(scenario, META1, proposal_id, true);
    vote_with_signer(scenario, META2, proposal_id, true);
    vote_with_signer(scenario, META3, proposal_id, true);
    refresh_with_signer(scenario, META3, proposal_id);
}

fun pass_meta_proposal_with_four_votes(scenario: &mut ts::Scenario, proposal_id: u64) {
    vote_with_signer(scenario, META1, proposal_id, true);
    vote_with_signer(scenario, META2, proposal_id, true);
    vote_with_signer(scenario, META3, proposal_id, true);
    vote_with_signer(scenario, META4, proposal_id, true);
    refresh_with_signer(scenario, META4, proposal_id);
}

fun append_bytes(payload: &mut vector<u8>, part: vector<u8>) {
    vector::append(payload, part);
}

fun compute_expected_event_digest(
    sequence: u64,
    event_type: u8,
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
    emitted_at_ms: u64,
): vector<u8> {
    let mut payload = bcs::to_bytes(&sequence);
    append_bytes(&mut payload, ROOT_AUTHORITY_DID);
    append_bytes(&mut payload, bcs::to_bytes(&event_type));
    append_bytes(&mut payload, bcs::to_bytes(&proposal_id));
    append_bytes(&mut payload, bcs::to_bytes(&committee_type));
    append_bytes(&mut payload, bcs::to_bytes(&target_address));
    append_bytes(&mut payload, bcs::to_bytes(&subject_type));
    append_bytes(&mut payload, subject_did);
    append_bytes(&mut payload, bcs::to_bytes(&subject_status));
    append_bytes(&mut payload, bcs::to_bytes(&authorized_domains));
    append_bytes(&mut payload, bcs::to_bytes(&effective_from_ms));
    append_bytes(&mut payload, bcs::to_bytes(&expires_at_ms));
    append_bytes(&mut payload, policy_hash);
    append_bytes(&mut payload, metadata_hash);
    append_bytes(&mut payload, previous_event_digest);
    append_bytes(&mut payload, bcs::to_bytes(&emitted_at_ms));
    hash::sha3_256(payload)
}

#[test]
fun test_init_sets_expected_committees() {
    bootstrap();

    let scenario = ts::begin(META1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::active_meta_admin_count(&bulletin_obj) == 4, 0);
        assert!(bulletin::active_admin_count(&bulletin_obj) == 4, 1);
        assert!(bulletin::meta_admin_count_total(&bulletin_obj) == 4, 3);
        assert!(bulletin::admin_count_total(&bulletin_obj) == 4, 4);
        assert!(bulletin::admin_threshold(&bulletin_obj) == 2, 2);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_root_authority_did_is_stored_in_bulletin() {
    bootstrap();

    let scenario = ts::begin(META1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::root_authority_did(&bulletin_obj) == ROOT_AUTHORITY_DID, 0);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_committee_enumeration_interfaces_return_bootstrap_members() {
    bootstrap();

    let scenario = ts::begin(META1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let (meta0, meta0_status) = bulletin::meta_admin_at(&bulletin_obj, 0);
        let (meta3, meta3_status) = bulletin::meta_admin_at(&bulletin_obj, 3);
        let (admin0, admin0_status) = bulletin::admin_at(&bulletin_obj, 0);
        let (admin3, admin3_status) = bulletin::admin_at(&bulletin_obj, 3);
        assert!(meta0 == META1, 5);
        assert!(meta0_status == MEMBER_ACTIVE, 6);
        assert!(meta3 == META4, 7);
        assert!(meta3_status == MEMBER_ACTIVE, 8);
        assert!(admin0 == ADMIN1, 9);
        assert!(admin0_status == MEMBER_ACTIVE, 10);
        assert!(admin3 == ADMIN4, 11);
        assert!(admin3_status == MEMBER_ACTIVE, 12);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_ALREADY_INITIALIZED)]
fun test_initialize_cannot_run_twice() {
    let mut scenario = ts::begin(META1);
    {
        let clock_obj = clock::create_for_testing(scenario.ctx());
        clock::share_for_testing(clock_obj);
        bulletin::init_for_testing(scenario.ctx());
        ts::next_tx(&mut scenario, META1);
        let mut init_state = ts::take_shared<bulletin::BulletinInitState>(&scenario);
        bulletin::override_init_package_address_for_testing(&mut init_state, TEST_PACKAGE_ID);
        let upgrade_cap_one = package::test_publish(object::id_from_address(TEST_PACKAGE_ID), scenario.ctx());
        bulletin::initialize(
            &mut init_state,
            ROOT_AUTHORITY_DID,
            vector[META1, META2, META3, META4],
            vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4],
            2,
            upgrade_cap_one,
            scenario.ctx(),
        );
        let upgrade_cap_two = package::test_publish(object::id_from_address(TEST_PACKAGE_ID), scenario.ctx());
        bulletin::initialize(
            &mut init_state,
            ROOT_AUTHORITY_DID,
            vector[META1, META2, META3, META4],
            vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4],
            2,
            upgrade_cap_two,
            scenario.ctx(),
        );
        ts::return_shared(init_state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_NOT_INIT_PUBLISHER)]
fun test_initialize_requires_publish_sender() {
    let mut scenario = ts::begin(META1);
    {
        let clock_obj = clock::create_for_testing(scenario.ctx());
        clock::share_for_testing(clock_obj);
        bulletin::init_for_testing(scenario.ctx());
        ts::next_tx(&mut scenario, ADMIN1);
        let mut init_state = ts::take_shared<bulletin::BulletinInitState>(&scenario);
        bulletin::override_init_package_address_for_testing(&mut init_state, TEST_PACKAGE_ID);
        let upgrade_cap = package::test_publish(object::id_from_address(TEST_PACKAGE_ID), scenario.ctx());
        bulletin::initialize(
            &mut init_state,
            ROOT_AUTHORITY_DID,
            vector[META1, META2, META3, META4],
            vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4],
            2,
            upgrade_cap,
            scenario.ctx(),
        );
        ts::return_shared(init_state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_UPGRADE_CAP_PACKAGE_MISMATCH)]
fun test_initialize_rejects_wrong_package_upgrade_cap() {
    let mut scenario = ts::begin(META1);
    {
        let clock_obj = clock::create_for_testing(scenario.ctx());
        clock::share_for_testing(clock_obj);
        bulletin::init_for_testing(scenario.ctx());
        ts::next_tx(&mut scenario, META1);
        let mut init_state = ts::take_shared<bulletin::BulletinInitState>(&scenario);
        bulletin::override_init_package_address_for_testing(&mut init_state, @0xB002);
        let upgrade_cap = package::test_publish(object::id_from_address(TEST_PACKAGE_ID), scenario.ctx());
        bulletin::initialize(
            &mut init_state,
            ROOT_AUTHORITY_DID,
            vector[META1, META2, META3, META4],
            vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4],
            2,
            upgrade_cap,
            scenario.ctx(),
        );
        ts::return_shared(init_state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_TOO_MANY_META_ADMINS)]
fun test_init_rejects_too_many_meta_admins() {
    bootstrap_with_committees(
        vector[META1, META2, META3, META4, META5, META6, META7, META8, META9, META10, META11, META12, META13, META14, META15, META16],
        vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4],
        2,
    );
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_TOO_MANY_ADMINS)]
fun test_init_rejects_too_many_admins() {
    bootstrap_with_committees(
        vector[META1, META2, META3, META4],
        vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4, ADMIN5, ADMIN6, ADMIN7, ADMIN8, ADMIN9, ADMIN10, ADMIN11, ADMIN12, ADMIN13, ADMIN14, ADMIN15, ADMIN16, ADMIN17, ADMIN18, ADMIN19, ADMIN20, ADMIN21, ADMIN22, ADMIN23, ADMIN24, ADMIN25, ADMIN26],
        2,
    );
}

#[test]
fun test_upgrade_manager_is_owned_by_publisher() {
    bootstrap();

    let scenario = ts::begin(META1);
    {
        let manager = ts::take_from_sender<bulletin::UpgradeManager>(&scenario);
        assert!(bulletin::upgrade_publisher(&manager) == META1, 0);
        assert!(bulletin::upgrade_version(&manager) == 1, 1);
        assert!(bulletin::upgrade_policy(&manager) == package::compatible_policy(), 2);
        ts::return_to_sender(&scenario, manager);
    };
    scenario.end();
}

#[test]
fun test_publisher_can_authorize_and_commit_package_upgrade() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        let mut manager = ts::take_from_sender<bulletin::UpgradeManager>(&scenario);
        let package_before = bulletin::upgrade_package_id(&manager);
        let ticket = bulletin::authorize_package_upgrade(
            &mut manager,
            package::compatible_policy(),
            b"oan-upgrade-digest",
            scenario.ctx(),
        );
        let receipt = package::test_upgrade(ticket);
        bulletin::commit_package_upgrade(&mut manager, receipt, scenario.ctx());
        let package_after = bulletin::upgrade_package_id(&manager);
        assert!(package_after != package_before, 0);
        assert!(bulletin::upgrade_version(&manager) == 2, 1);
        ts::return_to_sender(&scenario, manager);
    };
    scenario.end();
}

#[test]
fun test_publisher_can_restrict_upgrade_policy() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        let mut manager = ts::take_from_sender<bulletin::UpgradeManager>(&scenario);
        bulletin::restrict_upgrade_policy_to_additive(&mut manager, scenario.ctx());
        assert!(bulletin::upgrade_policy(&manager) == package::additive_policy(), 0);
        bulletin::restrict_upgrade_policy_to_dep_only(&mut manager, scenario.ctx());
        assert!(bulletin::upgrade_policy(&manager) == package::dep_only_policy(), 1);
        ts::return_to_sender(&scenario, manager);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_NOT_PACKAGE_PUBLISHER)]
fun test_non_publisher_cannot_authorize_package_upgrade() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        let manager = ts::take_from_sender<bulletin::UpgradeManager>(&scenario);
        transfer::public_transfer(manager, ADMIN1);
    };
    ts::next_tx(&mut scenario, ADMIN1);
    {
        let mut manager = ts::take_from_sender<bulletin::UpgradeManager>(&scenario);
        let ticket = bulletin::authorize_package_upgrade(
            &mut manager,
            package::compatible_policy(),
            b"unauthorized-upgrade",
            scenario.ctx(),
        );
        let receipt = package::test_upgrade(ticket);
        bulletin::commit_package_upgrade(&mut manager, receipt, scenario.ctx());
        ts::return_to_sender(&scenario, manager);
    };
    scenario.end();
}

#[test]
fun test_meta_committee_can_add_admin_after_three_votes() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        create_meta_add_admin5_proposal(&mut scenario);
    };
    {
        ts::next_tx(&mut scenario, META1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META2);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META3);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        bulletin::refresh_proposal_status(&mut bulletin_obj, 1, &clock_ref);
        assert!(bulletin::proposal_status(&bulletin_obj, 1) == 2, 3);
        assert!(bulletin::member_status(&bulletin_obj, 2, ADMIN5) == 1, 4);
        assert!(bulletin::active_admin_count(&bulletin_obj) == 5, 5);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 1, 6);
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_meta_cannot_add_admin_beyond_configured_maximum() {
    bootstrap_with_committees(
        vector[META1, META2, META3, META4],
        vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4, ADMIN5, ADMIN6, ADMIN7, ADMIN8, ADMIN9, ADMIN10, ADMIN11, ADMIN12, ADMIN13, ADMIN14, ADMIN15, ADMIN16, ADMIN17, ADMIN18, ADMIN19, ADMIN20, ADMIN21, ADMIN22, ADMIN23, ADMIN24, ADMIN25],
        2,
    );

    let mut scenario = ts::begin(META1);
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_ADD,
        ADMIN26,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-add-admin26",
        b"add-admin26",
        b"add-admin26",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 1);
    ts::next_tx(&mut scenario, META1);
    let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
    assert!(bulletin::proposal_status(&bulletin_obj, 1) == PROPOSAL_REJECTED, 0);
    assert!(bulletin::active_admin_count(&bulletin_obj) == 25, 1);
    assert!(bulletin::latest_event_sequence(&bulletin_obj) == 0, 2);
    ts::return_shared(bulletin_obj);
    scenario.end();
}

#[test]
fun test_meta_cannot_add_meta_beyond_configured_maximum() {
    bootstrap_with_committees(
        vector[META1, META2, META3, META4, META5, META6, META7, META8, META9, META10, META11, META12, META13, META14, META15],
        vector[ADMIN1, ADMIN2, ADMIN3, ADMIN4],
        2,
    );

    let mut scenario = ts::begin(META1);
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_META_ADD,
        META16,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-add-meta16",
        b"add-meta16",
        b"add-meta16",
        0,
        0,
        0,
    );
    vote_with_signer(&mut scenario, META1, 1, true);
    vote_with_signer(&mut scenario, META2, 1, true);
    vote_with_signer(&mut scenario, META3, 1, true);
    vote_with_signer(&mut scenario, META4, 1, true);
    vote_with_signer(&mut scenario, META5, 1, true);
    vote_with_signer(&mut scenario, META6, 1, true);
    vote_with_signer(&mut scenario, META7, 1, true);
    vote_with_signer(&mut scenario, META8, 1, true);
    vote_with_signer(&mut scenario, META9, 1, true);
    vote_with_signer(&mut scenario, META10, 1, true);
    vote_with_signer(&mut scenario, META11, 1, true);
    refresh_with_signer(&mut scenario, META11, 1);
    ts::next_tx(&mut scenario, META1);
    let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
    assert!(bulletin::proposal_status(&bulletin_obj, 1) == PROPOSAL_REJECTED, 0);
    assert!(bulletin::active_meta_admin_count(&bulletin_obj) == 15, 1);
    assert!(bulletin::latest_event_sequence(&bulletin_obj) == 0, 2);
    ts::return_shared(bulletin_obj);
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_DUPLICATE_VOTE)]
fun test_duplicate_vote_is_rejected() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        create_meta_add_admin5_proposal(&mut scenario);
    };
    {
        ts::next_tx(&mut scenario, META1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_cannot_disable_admin_below_minimum_active_count() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::create_proposal(
            &mut bulletin_obj,
            1,
            12,
            ADMIN1,
            vector[],
            0,
            vector[],
            b"policy",
            b"disable-admin1",
            b"disable-admin1",
            0,
            0,
            0,
            &clock_ref,
            scenario.ctx(),
        );
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META2);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META3);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        bulletin::refresh_proposal_status(&mut bulletin_obj, 1, &clock_ref);
        assert!(bulletin::proposal_status(&bulletin_obj, 1) == PROPOSAL_REJECTED, 0);
        assert!(bulletin::active_admin_count(&bulletin_obj) == 4, 1);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 0, 2);
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_TOO_MANY_PENDING_PROPOSALS)]
fun test_pending_proposal_cap_is_enforced() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    let mut created = 0u64;
    while (created < 256) {
        create_proposal_with_signer(
            &mut scenario,
            META1,
            COMMITTEE_META_ADMIN,
            ACTION_ADMIN_ADD,
            ADMIN5,
            vector[],
            SUBJECT_NONE,
            vector[],
            b"policy-pending-cap",
            b"pending-cap",
            b"pending-cap",
            0,
            0,
            0,
        );
        created = created + 1;
    };
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_ADD,
        ADMIN5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-over-cap",
        b"over-cap",
        b"over-cap",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test]
fun test_finalized_proposals_are_retained_without_blocking_new_pending_proposals() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    let mut created = 0u64;
    while (created < 255) {
        create_proposal_with_signer(
            &mut scenario,
            META1,
            COMMITTEE_META_ADMIN,
            ACTION_ADMIN_ADD,
            ADMIN5,
            vector[],
            SUBJECT_NONE,
            vector[],
            b"policy-fill",
            b"fill",
            b"fill",
            0,
            0,
            0,
        );
        created = created + 1;
    };
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_ADD,
        ADMIN5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-finalized",
        b"finalized",
        b"finalized",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 256);
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_ADD,
        ADMIN6,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-after-finalized",
        b"after-finalized",
        b"after-finalized",
        0,
        0,
        0,
    );
    ts::next_tx(&mut scenario, META1);
    let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
    assert!(bulletin::proposal_status(&bulletin_obj, 256) == PROPOSAL_PASSED, 0);
    assert!(bulletin::proposal_status(&bulletin_obj, 257) == PROPOSAL_PENDING, 0);
    assert!(bulletin::latest_event_sequence(&bulletin_obj) == 1, 1);
    ts::return_shared(bulletin_obj);
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INVALID_THRESHOLD)]
fun test_invalid_admin_threshold_update_is_rejected() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::create_proposal(
            &mut bulletin_obj,
            1,
            15,
            @0x0,
            vector[],
            0,
            vector[],
            b"policy",
            b"threshold-4",
            b"threshold-4",
            0,
            0,
            4,
            &clock_ref,
            scenario.ctx(),
        );
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META2);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, META3);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        bulletin::refresh_proposal_status(&mut bulletin_obj, 1, &clock_ref);
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_admin_threshold_snapshot_prevents_retroactive_lowering() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x330,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-snapshot",
        b"registrar-snapshot",
        b"registrar-snapshot",
        0,
        0,
        0,
    );
    vote_with_signer(&mut scenario, ADMIN1, 1, true);

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_THRESHOLD_UPDATE,
        @0x0,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-threshold-1",
        b"threshold-1",
        b"threshold-1",
        0,
        0,
        1,
    );
    pass_meta_proposal(&mut scenario, 2);

    refresh_with_signer(&mut scenario, ADMIN2, 1);
    ts::next_tx(&mut scenario, ADMIN1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::proposal_status(&bulletin_obj, 1) == PROPOSAL_PENDING, 90);
        assert!(bulletin::admin_threshold(&bulletin_obj) == 1, 91);
        ts::return_shared(bulletin_obj);
    };

    vote_with_signer(&mut scenario, ADMIN2, 1, true);
    refresh_with_signer(&mut scenario, ADMIN3, 1);
    ts::next_tx(&mut scenario, ADMIN1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::proposal_status(&bulletin_obj, 1) == PROPOSAL_PASSED, 92);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, REGISTRAR_DID) == STATUS_ACTIVE, 93);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_registrar_and_discovery_lifecycle() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    {
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::create_proposal(
            &mut bulletin_obj,
            2,
            21,
            @0x301,
            REGISTRAR_DID,
            1,
            vector[b"*"],
            b"policy-r1",
            b"registrar-authorize",
            b"registrar-authorize",
            0,
            0,
            0,
            &clock_ref,
            scenario.ctx(),
        );
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN2);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 1, true, &clock_ref, scenario.ctx());
        bulletin::refresh_proposal_status(&mut bulletin_obj, 1, &clock_ref);
        assert!(bulletin::subject_status(&bulletin_obj, 1, REGISTRAR_DID) == 1, 10);
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::create_proposal(
            &mut bulletin_obj,
            2,
            31,
            @0x302,
            DISCOVERY_DID,
            2,
            vector[b"finance_and_business", b"legal_services"],
            b"policy-d1",
            b"discovery-authorize",
            b"discovery-authorize",
            0,
            0,
            0,
            &clock_ref,
            scenario.ctx(),
        );
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 2, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN2);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 2, true, &clock_ref, scenario.ctx());
        bulletin::refresh_proposal_status(&mut bulletin_obj, 2, &clock_ref);
        assert!(bulletin::subject_status(&bulletin_obj, 2, DISCOVERY_DID) == 1, 11);
        assert!(bulletin::subject_domain_count(&bulletin_obj, 2, DISCOVERY_DID) == 2, 12);
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::create_proposal(
            &mut bulletin_obj,
            2,
            32,
            @0x302,
            DISCOVERY_DID,
            2,
            vector[b"finance_and_business", b"legal_services", b"technology"],
            b"policy-d2",
            b"discovery-update",
            b"discovery-update",
            0,
            0,
            0,
            &clock_ref,
            scenario.ctx(),
        );
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 3, true, &clock_ref, scenario.ctx());
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    {
        ts::next_tx(&mut scenario, ADMIN2);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = ts::take_shared<Clock>(&scenario);
        bulletin::vote(&mut bulletin_obj, 3, true, &clock_ref, scenario.ctx());
        bulletin::refresh_proposal_status(&mut bulletin_obj, 3, &clock_ref);
        assert!(bulletin::subject_domain_count(&bulletin_obj, 2, DISCOVERY_DID) == 3, 13);
        assert!(bulletin::subject_version(&bulletin_obj, 2, DISCOVERY_DID) == 2, 14);
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_event_digest_continuity_for_committee_events() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_meta_add_admin5_proposal(&mut scenario);
    pass_meta_proposal(&mut scenario, 1);
    ts::next_tx(&mut scenario, META1);

    let first_digest = {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let digest = bulletin::latest_event_digest(&bulletin_obj);
        assert!(
            digest == compute_expected_event_digest(
                1,
                ACTION_ADMIN_ADD,
                1,
                COMMITTEE_META_ADMIN,
                ADMIN5,
                vector[],
                SUBJECT_NONE,
                SUBJECT_NONE,
                vector[],
                0,
                0,
                b"policy",
                b"meta-admin-add",
                vector[],
                0,
            ),
            84
        );
        ts::return_shared(bulletin_obj);
        digest
    };

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_DISABLE,
        ADMIN4,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-disable-admin4",
        b"disable-admin4",
        b"disable-admin4",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 2);
    ts::next_tx(&mut scenario, META1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let second_digest = bulletin::latest_event_digest(&bulletin_obj);
        assert!(
            second_digest == compute_expected_event_digest(
                2,
                ACTION_ADMIN_DISABLE,
                2,
                COMMITTEE_META_ADMIN,
                ADMIN4,
                vector[],
                SUBJECT_NONE,
                SUBJECT_NONE,
                vector[],
                0,
                0,
                b"policy-disable-admin4",
                b"disable-admin4",
                first_digest,
                0,
            ),
            85
        );
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_event_digest_binds_subject_payload_updates() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_AUTHORIZE,
        @0x901,
        DISCOVERY_DID,
        SUBJECT_DISCOVERY,
        vector[b"finance_and_business", b"legal_services"],
        b"policy-d-auth",
        b"discovery-auth",
        b"discovery-auth",
        0,
        9000,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);
    ts::next_tx(&mut scenario, ADMIN1);

    let first_digest = {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let digest = bulletin::latest_event_digest(&bulletin_obj);
        assert!(
            digest == compute_expected_event_digest(
                1,
                ACTION_DISCOVERY_AUTHORIZE,
                1,
                COMMITTEE_ADMIN,
                @0x901,
                DISCOVERY_DID,
                SUBJECT_DISCOVERY,
                STATUS_ACTIVE,
                vector[b"finance_and_business", b"legal_services"],
                0,
                9000,
                b"policy-d-auth",
                b"discovery-auth",
                vector[],
                0,
            ),
            86
        );
        ts::return_shared(bulletin_obj);
        digest
    };

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_DOMAINS_UPDATE,
        @0x901,
        DISCOVERY_DID,
        SUBJECT_DISCOVERY,
        vector[b"finance_and_business", b"legal_services", b"technology"],
        b"policy-d-update",
        b"discovery-update",
        b"discovery-update",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 2);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let second_digest = bulletin::latest_event_digest(&bulletin_obj);
        assert!(
            second_digest == compute_expected_event_digest(
                2,
                ACTION_DISCOVERY_DOMAINS_UPDATE,
                2,
                COMMITTEE_ADMIN,
                @0x901,
                DISCOVERY_DID,
                SUBJECT_DISCOVERY,
                STATUS_ACTIVE,
                vector[b"finance_and_business", b"legal_services", b"technology"],
                0,
                9000,
                b"policy-d-update",
                b"discovery-update",
                first_digest,
                0,
            ),
            87
        );
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_subject_read_interfaces_for_active_discovery() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_AUTHORIZE,
        @0x902,
        DISCOVERY_DID,
        SUBJECT_DISCOVERY,
        vector[b"finance_and_business", b"legal_services"],
        b"policy-d-query",
        b"discovery-query",
        b"discovery-query",
        0,
        9000,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let (exists, status, version, effective_from_ms, expires_at_ms) =
            bulletin::subject_snapshot(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID);
        let (auth_exists, is_authorized, auth_status, auth_version, auth_effective_from_ms, auth_expires_at_ms) =
            bulletin::subject_authorization_snapshot_at(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID, 1);
        assert!(exists, 120);
        assert!(status == STATUS_ACTIVE, 121);
        assert!(version == 1, 122);
        assert!(effective_from_ms == 0, 123);
        assert!(expires_at_ms == 9000, 124);
        assert!(auth_exists, 141);
        assert!(is_authorized, 142);
        assert!(auth_status == STATUS_ACTIVE, 143);
        assert!(auth_version == 1, 144);
        assert!(auth_effective_from_ms == 0, 145);
        assert!(auth_expires_at_ms == 9000, 146);
        assert!(bulletin::subject_exists(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID), 125);
        assert!(bulletin::subject_is_authorized_at(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID, 1), 126);
        assert!(bulletin::discovery_is_authorized_at(&bulletin_obj, DISCOVERY_DID, 8999), 127);
        assert!(!bulletin::discovery_is_authorized_at(&bulletin_obj, DISCOVERY_DID, 9000), 128);
        assert!(bulletin::subject_policy_hash(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID) == b"policy-d-query", 129);
        assert!(bulletin::subject_metadata_hash(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID) == b"discovery-query", 130);
        assert!(
            bulletin::subject_authorized_domains(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID) ==
                vector[b"finance_and_business", b"legal_services"],
            131
        );
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_subject_read_interfaces_for_missing_subject() {
    bootstrap();

    let scenario = ts::begin(ADMIN1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let (exists, status, version, effective_from_ms, expires_at_ms) =
            bulletin::subject_snapshot(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing");
        let (auth_exists, is_authorized, auth_status, auth_version, auth_effective_from_ms, auth_expires_at_ms) =
            bulletin::subject_authorization_snapshot_at(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing", 1);
        assert!(!exists, 132);
        assert!(status == SUBJECT_NONE, 133);
        assert!(version == 0, 134);
        assert!(effective_from_ms == 0, 135);
        assert!(expires_at_ms == 0, 136);
        assert!(!auth_exists, 147);
        assert!(!is_authorized, 148);
        assert!(auth_status == SUBJECT_NONE, 149);
        assert!(auth_version == 0, 150);
        assert!(auth_effective_from_ms == 0, 151);
        assert!(auth_expires_at_ms == 0, 152);
        assert!(
            !bulletin::subject_exists(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing"),
            137
        );
        assert!(
            !bulletin::subject_is_authorized_at(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing", 1),
            138
        );
        assert!(
            !bulletin::registrar_is_authorized_at(&bulletin_obj, b"did:ans:registrar:missing", 1),
            139
        );
        assert!(
            !bulletin::vc_issuer_is_authorized_at(&bulletin_obj, b"did:ans:vc-issuer:missing", 1),
            140
        );
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing") == SUBJECT_NONE, 153);
        assert!(bulletin::subject_version(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing") == 0, 154);
        assert!(bulletin::subject_domain_count(&bulletin_obj, SUBJECT_DISCOVERY, b"did:ans:discovery:missing") == 0, 155);
        assert!(bulletin::subject_policy_hash(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing") == vector[], 156);
        assert!(bulletin::subject_metadata_hash(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:missing") == vector[], 157);
        assert!(bulletin::subject_authorized_domains(&bulletin_obj, SUBJECT_DISCOVERY, b"did:ans:discovery:missing") == vector[], 158);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_DUPLICATE_OR_UNSORTED_AUTHORIZED_DOMAIN)]
fun test_discovery_authorize_rejects_unsorted_or_duplicate_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_AUTHORIZE,
        @0x903,
        b"did:ans:discovery:unordered",
        SUBJECT_DISCOVERY,
        vector[b"legal_services", b"finance_and_business", b"finance_and_business"],
        b"policy-d-dup",
        b"discovery-dup",
        b"discovery-dup",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_NON_CANONICAL_AUTHORIZED_DOMAIN)]
fun test_discovery_authorize_rejects_non_canonical_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_AUTHORIZE,
        @0x904,
        b"did:ans:discovery:uppercase",
        SUBJECT_DISCOVERY,
        vector[b"Legal_Services"],
        b"policy-d-case",
        b"discovery-case",
        b"discovery-case",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test]
fun test_finalized_proposal_history_is_pruned_with_bounded_retention() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    let mut created = 0u64;
    while (created < 151) {
        create_proposal_with_signer(
            &mut scenario,
            META1,
            COMMITTEE_META_ADMIN,
            ACTION_ADMIN_ADD,
            if (created % 2 == 0) ADMIN5 else ADMIN6,
            vector[],
            SUBJECT_NONE,
            vector[],
            b"policy-history",
            b"history",
            b"history",
            0,
            0,
            0,
        );
        pass_meta_proposal(&mut scenario, created + 1);
        created = created + 1;
    };

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_ADD,
        ADMIN7,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-history-after-prune",
        b"history-after-prune",
        b"history-after-prune",
        0,
        0,
        0,
    );
    ts::next_tx(&mut scenario, META1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::proposal_status(&bulletin_obj, 152) == PROPOSAL_PENDING, 159);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_meta_can_disable_and_reenable_admin() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_meta_add_admin5_proposal(&mut scenario);
    pass_meta_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_DISABLE,
        ADMIN4,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-disable-admin4",
        b"disable-admin4",
        b"disable-admin4",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 2);
    ts::next_tx(&mut scenario, META1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::member_status(&bulletin_obj, COMMITTEE_ADMIN, ADMIN4) == 2, 30);
        assert!(bulletin::active_admin_count(&bulletin_obj) == 4, 31);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 2, 32);
        ts::return_shared(bulletin_obj);
    };

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_ENABLE,
        ADMIN4,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-enable-admin4",
        b"enable-admin4",
        b"enable-admin4",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 3);
    ts::next_tx(&mut scenario, META1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::member_status(&bulletin_obj, COMMITTEE_ADMIN, ADMIN4) == MEMBER_ACTIVE, 33);
        assert!(bulletin::active_admin_count(&bulletin_obj) == 5, 34);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 3, 35);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_meta_committee_lifecycle_for_meta_member() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_META_ADD,
        META5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-add-meta5",
        b"add-meta5",
        b"add-meta5",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_META_DISABLE,
        META5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-disable-meta5",
        b"disable-meta5",
        b"disable-meta5",
        0,
        0,
        0,
    );
    pass_meta_proposal_with_four_votes(&mut scenario, 2);
    ts::next_tx(&mut scenario, META1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::member_status(&bulletin_obj, COMMITTEE_META_ADMIN, META5) == MEMBER_DISABLED, 70);
        assert!(bulletin::active_meta_admin_count(&bulletin_obj) == 4, 71);
        ts::return_shared(bulletin_obj);
    };

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_META_ENABLE,
        META5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-enable-meta5",
        b"enable-meta5",
        b"enable-meta5",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 3);

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_META_REMOVE,
        META5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-remove-meta5",
        b"remove-meta5",
        b"remove-meta5",
        0,
        0,
        0,
    );
    pass_meta_proposal_with_four_votes(&mut scenario, 4);
    ts::next_tx(&mut scenario, META1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::member_status(&bulletin_obj, COMMITTEE_META_ADMIN, META5) == MEMBER_REMOVED, 72);
        assert!(bulletin::active_meta_admin_count(&bulletin_obj) == 4, 73);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 4, 74);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_meta_can_remove_admin_after_expansion() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_meta_add_admin5_proposal(&mut scenario);
    pass_meta_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_REMOVE,
        ADMIN5,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-remove-admin5",
        b"remove-admin5",
        b"remove-admin5",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 2);
    ts::next_tx(&mut scenario, META1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::member_status(&bulletin_obj, COMMITTEE_ADMIN, ADMIN5) == MEMBER_REMOVED, 75);
        assert!(bulletin::active_admin_count(&bulletin_obj) == 4, 76);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 2, 77);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_refresh_before_threshold_keeps_proposal_pending() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x401,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-pending",
        b"registrar-pending",
        b"registrar-pending",
        0,
        0,
        0,
    );
    vote_with_signer(&mut scenario, ADMIN1, 1, true);
    refresh_with_signer(&mut scenario, ADMIN3, 1);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::proposal_status(&bulletin_obj, 1) == 1, 40);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 0, 41);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_EMPTY_SUBJECT_DID)]
fun test_subject_actions_require_non_empty_did() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x402,
        vector[],
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-empty",
        b"registrar-empty",
        b"registrar-empty",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INVALID_SUBJECT_TIMING)]
fun test_subject_expiry_must_not_precede_effective_time() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x403,
        b"did:ans:registrar:timing",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-timing",
        b"registrar-timing",
        b"registrar-timing",
        200,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INVALID_SUBJECT_TIMING)]
fun test_subject_effective_time_cannot_be_in_future() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x402,
        b"did:ans:registrar:future-effective",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-future",
        b"registrar-future",
        b"registrar-future",
        1,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INVALID_SUBJECT_TIMING)]
fun test_subject_expiry_must_be_in_future_when_present() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    let clock_ref = advance_clock(&scenario, 10);
    ts::return_shared(clock_ref);
    ts::next_tx(&mut scenario, ADMIN1);
    let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
    let clock_ref = ts::take_shared<Clock>(&scenario);
    bulletin::create_proposal(
        &mut bulletin_obj,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x403,
        b"did:ans:registrar:expired-at-create",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-expired",
        b"registrar-expired",
        b"registrar-expired",
        0,
        5,
        0,
        &clock_ref,
        scenario.ctx(),
    );
    ts::return_shared(clock_ref);
    ts::return_shared(bulletin_obj);
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_EMPTY_REQUIRED_HASH)]
fun test_proposal_requires_non_empty_metadata_hash() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x404,
        b"did:ans:registrar:missing-metadata",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-meta",
        b"",
        b"registrar-metadata",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_EMPTY_REQUIRED_HASH)]
fun test_proposal_requires_non_empty_params_hash() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x405,
        b"did:ans:registrar:missing-params",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-params",
        b"registrar-params",
        b"",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_EMPTY_AUTHORIZED_DOMAIN)]
fun test_discovery_authorize_requires_non_empty_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_AUTHORIZE,
        @0x404,
        b"did:ans:discovery:empty-domains",
        SUBJECT_DISCOVERY,
        vector[],
        b"policy-d-empty",
        b"discovery-empty",
        b"discovery-empty",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test]
fun test_registrar_authorize_accepts_authorized_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x406,
        b"did:ans:registrar:with-domains",
        SUBJECT_REGISTRAR,
        vector[b"finance_and_business", b"legal_services"],
        b"policy-r-domains",
        b"registrar-domains",
        b"registrar-domains",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);
    ts::next_tx(&mut scenario, ADMIN1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:with-domains") == STATUS_ACTIVE, 159);
        assert!(
            bulletin::subject_authorized_domains(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:with-domains") ==
                vector[b"finance_and_business", b"legal_services"],
            160
        );
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_registrar_authorize_accepts_max_authorized_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x416,
        b"did:ans:registrar:max-domains",
        SUBJECT_REGISTRAR,
        vector[
            b"domain_001", b"domain_002", b"domain_003", b"domain_004", b"domain_005", b"domain_006",
            b"domain_007", b"domain_008", b"domain_009", b"domain_010", b"domain_011", b"domain_012",
            b"domain_013", b"domain_014", b"domain_015", b"domain_016", b"domain_017", b"domain_018",
            b"domain_019", b"domain_020", b"domain_021", b"domain_022", b"domain_023", b"domain_024",
            b"domain_025", b"domain_026", b"domain_027", b"domain_028", b"domain_029", b"domain_030",
            b"domain_031", b"domain_032", b"domain_033", b"domain_034", b"domain_035", b"domain_036",
            b"domain_037", b"domain_038", b"domain_039", b"domain_040", b"domain_041", b"domain_042",
            b"domain_043", b"domain_044", b"domain_045", b"domain_046", b"domain_047", b"domain_048",
            b"domain_049", b"domain_050", b"domain_051", b"domain_052", b"domain_053", b"domain_054",
            b"domain_055", b"domain_056", b"domain_057", b"domain_058", b"domain_059", b"domain_060",
            b"domain_061", b"domain_062", b"domain_063", b"domain_064", b"domain_065", b"domain_066",
            b"domain_067", b"domain_068", b"domain_069", b"domain_070", b"domain_071", b"domain_072",
            b"domain_073", b"domain_074", b"domain_075", b"domain_076", b"domain_077", b"domain_078",
            b"domain_079", b"domain_080", b"domain_081", b"domain_082", b"domain_083", b"domain_084",
            b"domain_085", b"domain_086", b"domain_087", b"domain_088", b"domain_089", b"domain_090",
            b"domain_091", b"domain_092", b"domain_093", b"domain_094", b"domain_095", b"domain_096",
            b"domain_097", b"domain_098", b"domain_099", b"domain_100", b"domain_101", b"domain_102",
            b"domain_103", b"domain_104", b"domain_105", b"domain_106", b"domain_107", b"domain_108",
            b"domain_109", b"domain_110", b"domain_111", b"domain_112", b"domain_113", b"domain_114",
            b"domain_115", b"domain_116"
        ],
        b"policy-r-max-domains",
        b"registrar-max-domains",
        b"registrar-max-domains",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);
    ts::next_tx(&mut scenario, ADMIN1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(
            bulletin::subject_authorized_domains(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:max-domains") ==
                vector[
                    b"domain_001", b"domain_002", b"domain_003", b"domain_004", b"domain_005", b"domain_006",
                    b"domain_007", b"domain_008", b"domain_009", b"domain_010", b"domain_011", b"domain_012",
                    b"domain_013", b"domain_014", b"domain_015", b"domain_016", b"domain_017", b"domain_018",
                    b"domain_019", b"domain_020", b"domain_021", b"domain_022", b"domain_023", b"domain_024",
                    b"domain_025", b"domain_026", b"domain_027", b"domain_028", b"domain_029", b"domain_030",
                    b"domain_031", b"domain_032", b"domain_033", b"domain_034", b"domain_035", b"domain_036",
                    b"domain_037", b"domain_038", b"domain_039", b"domain_040", b"domain_041", b"domain_042",
                    b"domain_043", b"domain_044", b"domain_045", b"domain_046", b"domain_047", b"domain_048",
                    b"domain_049", b"domain_050", b"domain_051", b"domain_052", b"domain_053", b"domain_054",
                    b"domain_055", b"domain_056", b"domain_057", b"domain_058", b"domain_059", b"domain_060",
                    b"domain_061", b"domain_062", b"domain_063", b"domain_064", b"domain_065", b"domain_066",
                    b"domain_067", b"domain_068", b"domain_069", b"domain_070", b"domain_071", b"domain_072",
                    b"domain_073", b"domain_074", b"domain_075", b"domain_076", b"domain_077", b"domain_078",
                    b"domain_079", b"domain_080", b"domain_081", b"domain_082", b"domain_083", b"domain_084",
                    b"domain_085", b"domain_086", b"domain_087", b"domain_088", b"domain_089", b"domain_090",
                    b"domain_091", b"domain_092", b"domain_093", b"domain_094", b"domain_095", b"domain_096",
                    b"domain_097", b"domain_098", b"domain_099", b"domain_100", b"domain_101", b"domain_102",
                    b"domain_103", b"domain_104", b"domain_105", b"domain_106", b"domain_107", b"domain_108",
                    b"domain_109", b"domain_110", b"domain_111", b"domain_112", b"domain_113", b"domain_114",
                    b"domain_115", b"domain_116"
                ],
            163
        );
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INPUT_TOO_LARGE)]
fun test_registrar_authorize_rejects_too_many_authorized_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x417,
        b"did:ans:registrar:too-many-domains",
        SUBJECT_REGISTRAR,
        vector[
            b"domain_001", b"domain_002", b"domain_003", b"domain_004", b"domain_005", b"domain_006",
            b"domain_007", b"domain_008", b"domain_009", b"domain_010", b"domain_011", b"domain_012",
            b"domain_013", b"domain_014", b"domain_015", b"domain_016", b"domain_017", b"domain_018",
            b"domain_019", b"domain_020", b"domain_021", b"domain_022", b"domain_023", b"domain_024",
            b"domain_025", b"domain_026", b"domain_027", b"domain_028", b"domain_029", b"domain_030",
            b"domain_031", b"domain_032", b"domain_033", b"domain_034", b"domain_035", b"domain_036",
            b"domain_037", b"domain_038", b"domain_039", b"domain_040", b"domain_041", b"domain_042",
            b"domain_043", b"domain_044", b"domain_045", b"domain_046", b"domain_047", b"domain_048",
            b"domain_049", b"domain_050", b"domain_051", b"domain_052", b"domain_053", b"domain_054",
            b"domain_055", b"domain_056", b"domain_057", b"domain_058", b"domain_059", b"domain_060",
            b"domain_061", b"domain_062", b"domain_063", b"domain_064", b"domain_065", b"domain_066",
            b"domain_067", b"domain_068", b"domain_069", b"domain_070", b"domain_071", b"domain_072",
            b"domain_073", b"domain_074", b"domain_075", b"domain_076", b"domain_077", b"domain_078",
            b"domain_079", b"domain_080", b"domain_081", b"domain_082", b"domain_083", b"domain_084",
            b"domain_085", b"domain_086", b"domain_087", b"domain_088", b"domain_089", b"domain_090",
            b"domain_091", b"domain_092", b"domain_093", b"domain_094", b"domain_095", b"domain_096",
            b"domain_097", b"domain_098", b"domain_099", b"domain_100", b"domain_101", b"domain_102",
            b"domain_103", b"domain_104", b"domain_105", b"domain_106", b"domain_107", b"domain_108",
            b"domain_109", b"domain_110", b"domain_111", b"domain_112", b"domain_113", b"domain_114",
            b"domain_115", b"domain_116", b"domain_117"
        ],
        b"policy-r-too-many-domains",
        b"registrar-too-many-domains",
        b"registrar-too-many-domains",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test]
fun test_registrar_domains_update_changes_active_registrar_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x407,
        b"did:ans:registrar:update-domains",
        SUBJECT_REGISTRAR,
        vector[b"finance_and_business", b"legal_services"],
        b"policy-r-auth",
        b"registrar-auth",
        b"registrar-auth",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_DOMAINS_UPDATE,
        @0x407,
        b"did:ans:registrar:update-domains",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-update",
        b"registrar-update",
        b"registrar-update",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 2);
    ts::next_tx(&mut scenario, ADMIN1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(
            bulletin::subject_authorized_domains(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:update-domains") ==
                vector[b"*"],
            161
        );
        assert!(bulletin::subject_version(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:update-domains") == 2, 162);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_NON_CANONICAL_AUTHORIZED_DOMAIN)]
fun test_registrar_authorize_rejects_non_canonical_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x408,
        b"did:ans:registrar:uppercase",
        SUBJECT_REGISTRAR,
        vector[b"Legal_Services"],
        b"policy-r-case",
        b"registrar-case",
        b"registrar-case",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_WILDCARD_MIXED_AUTHORIZED_DOMAIN)]
fun test_registrar_authorize_rejects_wildcard_mixed_with_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x409,
        b"did:ans:registrar:mixed-wildcard",
        SUBJECT_REGISTRAR,
        vector[b"*", b"legal_services"],
        b"policy-r-mixed",
        b"registrar-mixed",
        b"registrar-mixed",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INVALID_SUBJECT_TYPE)]
fun test_vc_issuer_authorize_rejects_authorized_domains() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_VC_ISSUER_AUTHORIZE,
        @0x407,
        b"did:ans:vc-issuer:with-domains",
        SUBJECT_VC_ISSUER,
        vector[b"unknown_domain"],
        b"policy-vc-domains",
        b"vc-domains",
        b"vc-domains",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INPUT_TOO_LARGE)]
fun test_oversized_metadata_is_rejected() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    let oversized = vector[
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    ];
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x405,
        b"did:ans:registrar:oversized",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        oversized,
        b"registrar-oversized",
        b"registrar-oversized",
        0,
        0,
        0,
    );
    scenario.end();
}

#[test]
fun test_meta_can_lower_admin_threshold_to_one() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_THRESHOLD_UPDATE,
        @0x0,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-threshold-1",
        b"threshold-1",
        b"threshold-1",
        0,
        0,
        1,
    );
    pass_meta_proposal(&mut scenario, 1);
    ts::next_tx(&mut scenario, META1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::admin_threshold(&bulletin_obj) == 1, 78);
        ts::return_shared(bulletin_obj);
    };

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x701,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-threshold1",
        b"registrar-threshold1",
        b"registrar-threshold1",
        0,
        0,
        0,
    );
    vote_with_signer(&mut scenario, ADMIN1, 2, true);
    refresh_with_signer(&mut scenario, ADMIN3, 2);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, REGISTRAR_DID) == STATUS_ACTIVE, 79);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 2, 80);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_MEMBER_NOT_FOUND)]
fun test_non_member_cannot_vote() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_meta_add_admin5_proposal(&mut scenario);
    vote_with_signer(&mut scenario, @0x999, 1, true);
    scenario.end();
}

#[test, expected_failure(abort_code = oan_bulletin::bulletin::E_INVALID_THRESHOLD)]
fun test_threshold_zero_update_is_rejected() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    create_proposal_with_signer(
        &mut scenario,
        META1,
        COMMITTEE_META_ADMIN,
        ACTION_ADMIN_THRESHOLD_UPDATE,
        @0x0,
        vector[],
        SUBJECT_NONE,
        vector[],
        b"policy-threshold-0",
        b"threshold-0",
        b"threshold-0",
        0,
        0,
        0,
    );
    pass_meta_proposal(&mut scenario, 1);
    scenario.end();
}

#[test]
fun test_registrar_suspend_recover_revoke_lifecycle() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x801,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-authorize",
        b"registrar-authorize",
        b"registrar-authorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_SUSPEND,
        @0x801,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[],
        b"policy-r-suspend",
        b"registrar-suspend",
        b"registrar-suspend",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 2);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_RECOVER,
        @0x801,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[],
        b"policy-r-recover",
        b"registrar-recover",
        b"registrar-recover",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 3);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_REVOKE,
        @0x801,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[],
        b"policy-r-revoke",
        b"registrar-revoke",
        b"registrar-revoke",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 4);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, REGISTRAR_DID) == STATUS_REVOKED, 81);
        assert!(bulletin::subject_version(&bulletin_obj, SUBJECT_REGISTRAR, REGISTRAR_DID) == 4, 82);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 4, 83);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_reauthorize_revoked_registrar_is_rejected() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x811,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-authorize",
        b"registrar-authorize",
        b"registrar-authorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_REVOKE,
        @0x811,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[],
        b"policy-r-revoke",
        b"registrar-revoke",
        b"registrar-revoke",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 2);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x811,
        REGISTRAR_DID,
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-reauthorize",
        b"registrar-reauthorize",
        b"registrar-reauthorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 3);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::proposal_status(&bulletin_obj, 3) == PROPOSAL_REJECTED, 94);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, REGISTRAR_DID) == STATUS_REVOKED, 95);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_reauthorize_suspended_registrar_is_rejected() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x812,
        b"did:ans:registrar:suspended",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-authorize",
        b"registrar-authorize",
        b"registrar-authorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_SUSPEND,
        @0x812,
        b"did:ans:registrar:suspended",
        SUBJECT_REGISTRAR,
        vector[],
        b"policy-r-suspend",
        b"registrar-suspend",
        b"registrar-suspend",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 2);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x812,
        b"did:ans:registrar:suspended",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-reauthorize",
        b"registrar-reauthorize",
        b"registrar-reauthorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 3);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::proposal_status(&bulletin_obj, 3) == PROPOSAL_REJECTED, 96);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:suspended") == STATUS_SUSPENDED, 97);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_stale_suspend_proposal_is_rejected_instead_of_sticking_pending() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_AUTHORIZE,
        @0x813,
        b"did:ans:registrar:stale",
        SUBJECT_REGISTRAR,
        vector[b"*"],
        b"policy-r-authorize",
        b"registrar-authorize",
        b"registrar-authorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_SUSPEND,
        @0x813,
        b"did:ans:registrar:stale",
        SUBJECT_REGISTRAR,
        vector[],
        b"policy-r-suspend-1",
        b"registrar-suspend-1",
        b"registrar-suspend-1",
        0,
        0,
        0,
    );
    vote_with_signer(&mut scenario, ADMIN1, 2, true);
    vote_with_signer(&mut scenario, ADMIN2, 2, true);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_REGISTRAR_SUSPEND,
        @0x813,
        b"did:ans:registrar:stale",
        SUBJECT_REGISTRAR,
        vector[],
        b"policy-r-suspend-2",
        b"registrar-suspend-2",
        b"registrar-suspend-2",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 3);

    refresh_with_signer(&mut scenario, ADMIN3, 2);
    ts::next_tx(&mut scenario, ADMIN1);
    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::proposal_status(&bulletin_obj, 2) == PROPOSAL_REJECTED, 98);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_REGISTRAR, b"did:ans:registrar:stale") == STATUS_SUSPENDED, 99);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_discovery_suspend_recover_revoke_lifecycle() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_AUTHORIZE,
        @0x501,
        DISCOVERY_DID,
        SUBJECT_DISCOVERY,
        vector[b"finance_and_business", b"legal_services"],
        b"policy-d-authorize",
        b"discovery-authorize",
        b"discovery-authorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_SUSPEND,
        @0x501,
        DISCOVERY_DID,
        SUBJECT_DISCOVERY,
        vector[],
        b"policy-d-suspend",
        b"discovery-suspend",
        b"discovery-suspend",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 2);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID) == STATUS_SUSPENDED, 53);
        ts::return_shared(bulletin_obj);
    };

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_RECOVER,
        @0x501,
        DISCOVERY_DID,
        SUBJECT_DISCOVERY,
        vector[],
        b"policy-d-recover",
        b"discovery-recover",
        b"discovery-recover",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 3);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID) == STATUS_ACTIVE, 54);
        ts::return_shared(bulletin_obj);
    };

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_DISCOVERY_REVOKE,
        @0x501,
        DISCOVERY_DID,
        SUBJECT_DISCOVERY,
        vector[],
        b"policy-d-revoke",
        b"discovery-revoke",
        b"discovery-revoke",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 4);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID) == STATUS_REVOKED, 50);
        assert!(bulletin::subject_version(&bulletin_obj, SUBJECT_DISCOVERY, DISCOVERY_DID) == 4, 51);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 4, 52);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_vc_issuer_authorize_suspend_recover_and_revoke() {
    bootstrap();

    let mut scenario = ts::begin(ADMIN1);
    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_VC_ISSUER_AUTHORIZE,
        @0x601,
        VC_ISSUER_DID,
        SUBJECT_VC_ISSUER,
        vector[],
        b"policy-vc-authorize",
        b"vc-authorize",
        b"vc-authorize",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 1);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_VC_ISSUER_SUSPEND,
        @0x601,
        VC_ISSUER_DID,
        SUBJECT_VC_ISSUER,
        vector[],
        b"policy-vc-suspend",
        b"vc-suspend",
        b"vc-suspend",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 2);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_VC_ISSUER_RECOVER,
        @0x601,
        VC_ISSUER_DID,
        SUBJECT_VC_ISSUER,
        vector[],
        b"policy-vc-recover",
        b"vc-recover",
        b"vc-recover",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 3);

    create_proposal_with_signer(
        &mut scenario,
        ADMIN1,
        COMMITTEE_ADMIN,
        ACTION_VC_ISSUER_REVOKE,
        @0x601,
        VC_ISSUER_DID,
        SUBJECT_VC_ISSUER,
        vector[],
        b"policy-vc-revoke",
        b"vc-revoke",
        b"vc-revoke",
        0,
        0,
        0,
    );
    pass_admin_proposal(&mut scenario, 4);
    ts::next_tx(&mut scenario, ADMIN1);

    {
        let bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        assert!(bulletin::subject_status(&bulletin_obj, SUBJECT_VC_ISSUER, VC_ISSUER_DID) == STATUS_REVOKED, 60);
        assert!(bulletin::subject_version(&bulletin_obj, SUBJECT_VC_ISSUER, VC_ISSUER_DID) == 4, 61);
        assert!(bulletin::latest_event_sequence(&bulletin_obj) == 4, 62);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}

#[test]
fun test_proposal_expires_after_window() {
    bootstrap();

    let mut scenario = ts::begin(META1);
    {
        create_meta_add_admin5_proposal(&mut scenario);
    };
    {
        ts::next_tx(&mut scenario, META1);
        let mut bulletin_obj = ts::take_shared<bulletin::Bulletin>(&scenario);
        let clock_ref = advance_clock(&scenario, 864000001);
        bulletin::refresh_proposal_status(&mut bulletin_obj, 1, &clock_ref);
        assert!(bulletin::proposal_status(&bulletin_obj, 1) == 3, 20);
        ts::return_shared(clock_ref);
        ts::return_shared(bulletin_obj);
    };
    scenario.end();
}
