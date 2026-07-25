//
//  MenuBarItemFailureLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
@testable import Thaw
import XCTest

/// Covers the ledger's contract along both of its dimensions: the
/// session-scoped backoff that keeps bulk apply off a failing item, and
/// the persisted mark that remembers an owner which never answers.
///
/// The two share a key and a clearing rule, so the tests that matter most
/// are the ones asserting they move together — one success clears both,
/// and a failure that is not an unresponsive owner extends the backoff
/// without ever earning a mark.
///
/// The ledger writes through to `UserDefaults.standard`, so every test
/// saves and restores the key it touches rather than leaving the running
/// user's domain modified.
@MainActor
final class MenuBarItemFailureLedgerTests: XCTestCase {
    private var savedValue: Any?

    override func setUp() {
        super.setUp()
        savedValue = Defaults.object(forKey: .unresponsiveMenuBarItems)
        Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
    }

    override func tearDown() {
        if let savedValue {
            Defaults.set(savedValue, forKey: .unresponsiveMenuBarItems)
        } else {
            Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
        }
        savedValue = nil
        super.tearDown()
    }

    /// A minimal item standing in for one owned by the named bundle.
    private func item(_ namespace: String, _ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(namespace), title: title),
            windowID: 1,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: title,
            isOnScreen: true
        )
    }

    /// An item whose namespace is regenerated every session.
    private func ephemeralItem() -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .uuid(UUID()), title: "Item-0"),
            windowID: 1,
            ownerPID: 1,
            sourcePID: nil,
            bounds: .zero,
            title: "Item-0",
            isOnScreen: true
        )
    }

    func testUnknownItemIsNotUnresponsive() {
        let ledger = MenuBarItemFailureLedger()
        XCTAssertFalse(ledger.isUnresponsive(item("at.obdev.littlesnitch", "Item-0")))
    }

    func testASingleFailureDoesNotMarkAnItem() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        XCTAssertFalse(ledger.isUnresponsive(item))
        XCTAssertNil(Defaults.object(forKey: .unresponsiveMenuBarItems))
    }

    func testASecondFailureMarksTheItem() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        XCTAssertTrue(ledger.isUnresponsive(item))
    }

    func testASuccessResetsTheProvisionalFailure() {
        // Two failures separated by a success are two unrelated blips, not
        // an owner that never answers.
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordSuccess(for: item)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        XCTAssertFalse(ledger.isUnresponsive(item))
    }

    func testMarkSurvivesANewStore() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let first = MenuBarItemFailureLedger()
        first.recordFailure(for: item, kind: .unresponsiveOwner)
        first.recordFailure(for: item, kind: .unresponsiveOwner)

        // A second instance reads only what was persisted, which is what a
        // relaunch does.
        XCTAssertTrue(MenuBarItemFailureLedger().isUnresponsive(item))
    }

    func testSuccessClearsTheRecordForGood() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordSuccess(for: item)

        XCTAssertFalse(ledger.isUnresponsive(item))
        XCTAssertFalse(MenuBarItemFailureLedger().isUnresponsive(item))
    }

    func testRecordsAreScopedToTheExactItem() {
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item("at.obdev.littlesnitch", "Item-0"), kind: .unresponsiveOwner)
        ledger.recordFailure(for: item("at.obdev.littlesnitch", "Item-0"), kind: .unresponsiveOwner)

        XCTAssertFalse(ledger.isUnresponsive(item("at.obdev.littlesnitch", "Item-1")))
        XCTAssertFalse(ledger.isUnresponsive(item("com.example.other", "Item-0")))
    }

    func testItemsWithoutAStableNamespaceAreNotRecorded() {
        // A UUID namespace is reassigned every session, so recording one
        // would persist a key that can never match again.
        let ephemeral = ephemeralItem()
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: ephemeral, kind: .unresponsiveOwner)
        ledger.recordFailure(for: ephemeral, kind: .unresponsiveOwner)

        XCTAssertFalse(ledger.isUnresponsive(ephemeral))
        XCTAssertNil(Defaults.object(forKey: .unresponsiveMenuBarItems))
    }

    func testRemoveAllForgetsEverything() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.removeAll()

        XCTAssertFalse(ledger.isUnresponsive(item))
        XCTAssertNil(Defaults.object(forKey: .unresponsiveMenuBarItems))
    }

    // MARK: Backoff

    func testUnknownItemIsNotUnderBackoff() {
        let ledger = MenuBarItemFailureLedger()
        XCTAssertFalse(ledger.isUnderBackoff(key: item("at.obdev.littlesnitch", "Item-0").uniqueIdentifier))
    }

    func testASingleFailureOpensTheBackoffWindow() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)

        XCTAssertTrue(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
    }

    func testBackoffLapsesOnceItsWindowHasPassed() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)

        // One failure buys 30 seconds and not a second more.
        XCTAssertTrue(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now.advanced(by: .seconds(29))))
        XCTAssertFalse(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now.advanced(by: .seconds(30))))
    }

    func testRepeatedFailuresWidenTheBackoffWindow() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)
        ledger.recordFailure(for: item, kind: .other, now: now)

        // Two failures, so 60 seconds — past where one would have lapsed.
        XCTAssertTrue(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now.advanced(by: .seconds(45))))
    }

    func testFailuresThatAreNotUnresponsiveOwnersNeverEarnAMark() {
        // A move that simply did not land says nothing about whether the
        // owner is answering, however often it happens.
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .other)
        ledger.recordFailure(for: item, kind: .other)
        ledger.recordFailure(for: item, kind: .other)

        XCTAssertFalse(ledger.isUnresponsive(item))
        XCTAssertNil(Defaults.object(forKey: .unresponsiveMenuBarItems))
    }

    func testOneSuccessClearsBothTheBackoffAndTheMark() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .unresponsiveOwner, now: now)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner, now: now)
        XCTAssertTrue(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
        XCTAssertTrue(ledger.isUnresponsive(item))

        ledger.recordSuccess(for: item)

        XCTAssertFalse(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
        XCTAssertFalse(ledger.isUnresponsive(item))
    }

    func testRemoveAllAlsoClearsTheBackoff() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)
        ledger.removeAll()

        XCTAssertFalse(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
    }

    func testUnstableItemsStillGetBackoff() {
        // No persisted mark for them, but a session's worth of skipping is
        // still worth having.
        let ephemeral = ephemeralItem()
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: ephemeral, kind: .unresponsiveOwner, now: now)

        XCTAssertTrue(ledger.isUnderBackoff(key: ephemeral.uniqueIdentifier, now: now))
    }
}
