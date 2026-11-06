//
//  MenuBarItemFailureLedgerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("The failure ledger marks unresponsive, unmovable and stranded items", .scratchDefaults)
struct MenuBarItemFailureLedgerTests {
    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private func makeItem(_ title: String, namespace: MenuBarItemTag.Namespace? = nil) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: namespace ?? .string("com.example.ledger"),
                title: title,
                instanceIndex: 0
            ),
            windowID: 4242,
            ownerPID: 999_992,
            sourcePID: 999_992,
            bounds: CGRect(x: 900, y: 0, width: 22, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A lone unresponsive failure is provisional and a second one marks and persists")
    func unresponsiveNeedsTwoStrikes() {
        let ledger = MenuBarItemFailureLedger()
        let item = makeItem("Clock")

        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        #expect(!ledger.isUnresponsive(item))
        #expect(Defaults.dictionary(forKey: .unresponsiveMenuBarItems) == nil)

        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        #expect(ledger.isUnresponsive(item))
        let stored = Defaults.dictionary(forKey: .unresponsiveMenuBarItems) as? [String: Double]
        #expect(stored?.keys.contains(item.uniqueIdentifier) == true)
        #expect(Defaults.string(forKey: .menuBarFailureLedgerVersion) == buildVersion)
    }

    @Test("A marked item stays marked on a third failure")
    func repeatedFailureKeepsMark() {
        let ledger = MenuBarItemFailureLedger()
        let item = makeItem("Repeat")
        for _ in 0 ..< 3 {
            ledger.recordFailure(for: item, kind: .cannotComplete)
        }
        #expect(ledger.cannotCompleteMarked(item))
        #expect(!ledger.isUnresponsive(item))
    }

    @Test("Provisional strikes do not count across kinds")
    func provisionalStrikesStayPerKind() {
        let ledger = MenuBarItemFailureLedger()
        let item = makeItem("Mixed")

        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .cannotComplete)
        ledger.recordFailure(for: item, kind: .other)

        #expect(!ledger.isUnresponsive(item))
        #expect(!ledger.cannotCompleteMarked(item))
    }

    @Test("Items with a per-session UUID namespace are never marked")
    func uuidNamespaceIsNotRecorded() {
        let ledger = MenuBarItemFailureLedger()
        let item = makeItem("Ephemeral", namespace: .uuid(UUID()))

        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordStrand(for: item)

        #expect(!ledger.isUnresponsive(item))
        #expect(!ledger.strandedMarked(item))
    }

    @Test("A strand marks at once and a success clears every verdict")
    func strandMarksImmediatelyAndSuccessClears() {
        let ledger = MenuBarItemFailureLedger()
        let item = makeItem("Stranded")

        ledger.recordStrand(for: item)
        ledger.recordStrand(for: item)
        ledger.recordFailure(for: item, kind: .cannotComplete)
        ledger.recordFailure(for: item, kind: .cannotComplete)
        #expect(ledger.strandedMarked(item))
        #expect(ledger.cannotCompleteMarked(item))

        ledger.recordSuccess(for: item)

        #expect(!ledger.strandedMarked(item))
        #expect(!ledger.cannotCompleteMarked(item))
        #expect(Defaults.dictionary(forKey: .strandedMenuBarItems) == nil)
        #expect(Defaults.dictionary(forKey: .cannotCompleteMenuBarItems) == nil)
    }

    @Test("A success also drops a provisional strike")
    func successDropsProvisionalStrike() {
        let ledger = MenuBarItemFailureLedger()
        let item = makeItem("Flaky")

        ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        ledger.recordSuccess(for: item)
        ledger.recordFailure(for: item, kind: .unresponsiveOwner)

        #expect(!ledger.isUnresponsive(item))
    }

    @Test("Removing everything clears persisted marks")
    func removeAllClearsStore() {
        let ledger = MenuBarItemFailureLedger()
        let item = makeItem("Gone")
        ledger.recordStrand(for: item)

        ledger.removeAll()

        #expect(!ledger.strandedMarked(item))
        #expect(Defaults.dictionary(forKey: .strandedMenuBarItems) == nil)
        // A second call with nothing stored is a no-op.
        ledger.removeAll()
        #expect(Defaults.dictionary(forKey: .unresponsiveMenuBarItems) == nil)
    }

    @Test("Marks persisted under the current build load into a new ledger")
    func marksSurviveRelaunch() {
        let item = makeItem("Survivor")
        do {
            let ledger = MenuBarItemFailureLedger()
            ledger.recordFailure(for: item, kind: .unresponsiveOwner)
            ledger.recordFailure(for: item, kind: .unresponsiveOwner)
        }

        let reloaded = MenuBarItemFailureLedger()

        #expect(reloaded.isUnresponsive(item))
    }

    @Test("A build change drops every persisted mark")
    func buildChangeDropsMarks() {
        let item = makeItem("Old")
        let recent = Date.now.timeIntervalSinceReferenceDate
        Defaults.set([item.uniqueIdentifier: recent], forKey: .unresponsiveMenuBarItems)
        Defaults.set([item.uniqueIdentifier: recent], forKey: .strandedMenuBarItems)
        Defaults.set("some-other-build", forKey: .menuBarFailureLedgerVersion)

        let ledger = MenuBarItemFailureLedger()

        #expect(!ledger.isUnresponsive(item))
        #expect(!ledger.strandedMarked(item))
        #expect(Defaults.dictionary(forKey: .unresponsiveMenuBarItems) == nil)
        #expect(Defaults.string(forKey: .menuBarFailureLedgerVersion) == buildVersion)
    }

    @Test("Expired marks are dropped on load and fresh ones are kept")
    func expiredMarksAreDroppedOnLoad() {
        let fresh = makeItem("Fresh")
        let stale = makeItem("Stale")
        let now = Date.now.timeIntervalSinceReferenceDate
        let fifteenDays: TimeInterval = 60 * 60 * 24 * 15
        let twoDays: TimeInterval = 60 * 60 * 24 * 2
        Defaults.set(
            [fresh.uniqueIdentifier: now, stale.uniqueIdentifier: now - fifteenDays],
            forKey: .cannotCompleteMenuBarItems
        )
        Defaults.set([stale.uniqueIdentifier: now - twoDays], forKey: .strandedMenuBarItems)
        Defaults.set(buildVersion, forKey: .menuBarFailureLedgerVersion)

        let ledger = MenuBarItemFailureLedger()

        #expect(ledger.cannotCompleteMarked(fresh))
        #expect(!ledger.cannotCompleteMarked(stale))
        #expect(!ledger.strandedMarked(stale))
        let stored = Defaults.dictionary(forKey: .cannotCompleteMenuBarItems) as? [String: Double]
        #expect(stored?.keys.sorted() == [fresh.uniqueIdentifier])
        #expect(Defaults.dictionary(forKey: .strandedMenuBarItems) == nil)
    }
}
