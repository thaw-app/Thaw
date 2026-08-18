//
//  MenuBarItemFailureLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

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
@Suite("Menu bar item failure ledger", .serialized)
final class MenuBarItemFailureLedgerTests {
    private let savedValue: Any?
    private let savedBuildValue: Any?

    init() {
        savedValue = Defaults.object(forKey: .unresponsiveMenuBarItems)
        savedBuildValue = Defaults.object(forKey: .unresponsiveMenuBarItemsBuild)
        Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
        Defaults.removeObject(forKey: .unresponsiveMenuBarItemsBuild)
    }

    /// Isolated so the non-Sendable snapshot is reachable here; the suite is
    /// already `@MainActor`.
    @MainActor
    deinit {
        if let savedValue {
            Defaults.set(savedValue, forKey: .unresponsiveMenuBarItems)
        } else {
            Defaults.removeObject(forKey: .unresponsiveMenuBarItems)
        }
        if let savedBuildValue {
            Defaults.set(savedBuildValue, forKey: .unresponsiveMenuBarItemsBuild)
        } else {
            Defaults.removeObject(forKey: .unresponsiveMenuBarItemsBuild)
        }
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

    /// Records exactly as many unresponsive-owner failures as it takes to
    /// earn a mark, for tests where being marked is setup rather than the
    /// thing under test.
    ///
    /// The threshold itself is pinned by ``aSecondFailureStillDoesNotMark``
    /// and ``aThirdFailureMarksTheItem``, so it lives as a literal in
    /// exactly one place here.
    private func failUntilMarked(
        _ ledger: MenuBarItemFailureLedger,
        _ item: MenuBarItem,
        now: ContinuousClock.Instant = .now
    ) {
        for _ in 0..<3 {
            ledger.recordFailure(for: item, kind: .unresponsiveOwner, now: now)
        }
    }

    @Test("An item the ledger has never seen is not unresponsive")
    func unknownItemIsNotUnresponsive() {
        let ledger = MenuBarItemFailureLedger()
        #expect(!ledger.isUnresponsive(item("at.obdev.littlesnitch", "Item-0")))
    }

    @Test("A single failure does not mark an item")
    func aSingleFailureDoesNotMarkAnItem() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        #expect(!ledger.isUnresponsive(item))
        #expect(Defaults.object(forKey: .unresponsiveMenuBarItems) == nil)
    }

    @Test("A second failure still does not mark an item")
    func aSecondFailureStillDoesNotMark() {
        // Two failed moves is thin evidence during a startup restore wave,
        // where contention alone can cost an item its budget twice (#687).
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        #expect(!ledger.isUnresponsive(item))
        #expect(Defaults.object(forKey: .unresponsiveMenuBarItems) == nil)
    }

    @Test("A third failure marks the item")
    func aThirdFailureMarksTheItem() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        #expect(ledger.isUnresponsive(item))
    }

    @Test("A success resets the run of failures rather than decrementing it")
    func aSuccessResetsTheProvisionalFailure() {
        // Failures separated by a success are unrelated blips, not an owner
        // that never answers, so the count starts over rather than carrying.
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        failUntilMarked(ledger, item)
        ledger.recordSuccess(for: item)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        #expect(!ledger.isUnresponsive(item))
    }

    @Test("A mark survives a new store")
    func markSurvivesANewStore() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let first = MenuBarItemFailureLedger()
        failUntilMarked(first, item)

        // A second instance reads only what was persisted, which is what a
        // relaunch does.
        #expect(MenuBarItemFailureLedger().isUnresponsive(item))
    }

    @Test("A success clears the record for good")
    func successClearsTheRecordForGood() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordSuccess(for: item)

        #expect(!ledger.isUnresponsive(item))
        #expect(!MenuBarItemFailureLedger().isUnresponsive(item))
    }

    @Test("Records are scoped to the exact item")
    func recordsAreScopedToTheExactItem() {
        let ledger = MenuBarItemFailureLedger()
        failUntilMarked(ledger, item("at.obdev.littlesnitch", "Item-0"))

        #expect(!ledger.isUnresponsive(item("at.obdev.littlesnitch", "Item-1")))
        #expect(!ledger.isUnresponsive(item("com.example.other", "Item-0")))
    }

    @Test("An item without a stable namespace is never recorded")
    func itemsWithoutAStableNamespaceAreNotRecorded() {
        // A UUID namespace is reassigned every session, so recording one
        // would persist a key that can never match again.
        let ephemeral = ephemeralItem()
        let ledger = MenuBarItemFailureLedger()
        failUntilMarked(ledger, ephemeral)

        #expect(!ledger.isUnresponsive(ephemeral))
        #expect(Defaults.object(forKey: .unresponsiveMenuBarItems) == nil)
    }

    @Test("removeAll forgets everything")
    func removeAllForgetsEverything() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        failUntilMarked(ledger, item)
        ledger.removeAll()

        #expect(!ledger.isUnresponsive(item))
        #expect(Defaults.object(forKey: .unresponsiveMenuBarItems) == nil)
    }

    // MARK: Backoff

    @Test("An item the ledger has never seen is not under backoff")
    func unknownItemIsNotUnderBackoff() {
        let ledger = MenuBarItemFailureLedger()
        #expect(!ledger.isUnderBackoff(key: item("at.obdev.littlesnitch", "Item-0").uniqueIdentifier))
    }

    @Test("A single failure opens the backoff window")
    func aSingleFailureOpensTheBackoffWindow() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)

        #expect(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
    }

    @Test("Backoff lapses once its window has passed")
    func backoffLapsesOnceItsWindowHasPassed() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)

        // One failure buys 30 seconds and not a second more.
        #expect(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now.advanced(by: .seconds(29))))
        #expect(!ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now.advanced(by: .seconds(30))))
    }

    @Test("Repeated failures widen the backoff window")
    func repeatedFailuresWidenTheBackoffWindow() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)
        ledger.recordFailure(for: item, kind: .other, now: now)

        // Two failures, so 60 seconds — past where one would have lapsed.
        #expect(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now.advanced(by: .seconds(45))))
    }

    @Test("Failures that are not unresponsive owners never earn a mark")
    func failuresThatAreNotUnresponsiveOwnersNeverEarnAMark() {
        // A move that simply did not land says nothing about whether the
        // owner is answering, however often it happens.
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        ledger.recordFailure(for: item, kind: .other)
        ledger.recordFailure(for: item, kind: .other)
        ledger.recordFailure(for: item, kind: .other)

        #expect(!ledger.isUnresponsive(item))
        #expect(Defaults.object(forKey: .unresponsiveMenuBarItems) == nil)
    }

    @Test("One success clears both the backoff and the mark")
    func oneSuccessClearsBothTheBackoffAndTheMark() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        failUntilMarked(ledger, item, now: now)
        #expect(ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
        #expect(ledger.isUnresponsive(item))

        ledger.recordSuccess(for: item)

        #expect(!ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
        #expect(!ledger.isUnresponsive(item))
    }

    @Test("removeAll also clears the backoff")
    func removeAllAlsoClearsTheBackoff() {
        let item = item("at.obdev.littlesnitch", "Item-0")
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: item, kind: .other, now: now)
        ledger.removeAll()

        #expect(!ledger.isUnderBackoff(key: item.uniqueIdentifier, now: now))
    }

    @Test("An item without a stable namespace still gets a backoff")
    func unstableItemsStillGetBackoff() {
        // No persisted mark for them, but a session's worth of skipping is
        // still worth having.
        let ephemeral = ephemeralItem()
        let ledger = MenuBarItemFailureLedger()
        let now = ContinuousClock.Instant.now
        ledger.recordFailure(for: ephemeral, kind: .unresponsiveOwner, now: now)

        #expect(ledger.isUnderBackoff(key: ephemeral.uniqueIdentifier, now: now))
    }
}
