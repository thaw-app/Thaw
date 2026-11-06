//
//  RevealRepairTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A bare item manager runs Standard hiding with nothing switched on for a reveal.
@MainActor
@Suite("Reveal repair")
struct RevealRepairTests {
    private func makeItem(title: String = "Status", x: CGFloat = 1000) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.reveal"), title: title, instanceIndex: 0),
            windowID: 401,
            ownerPID: 999_995,
            sourcePID: 999_995,
            bounds: CGRect(x: x, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("An item already in its section is not moved")
    func placedItemStays() {
        let manager = MenuBarItemManager()
        #expect(!manager.revealRepairMoves(makeItem(), isMisplaced: false))
    }

    @Test("Under Standard hiding a misplaced item is moved")
    func misplacedItemMoves() {
        let manager = MenuBarItemManager()
        #expect(manager.revealRepairMoves(makeItem(), isMisplaced: true))
    }

    @Test("An item whose write MenuBarAgent ignored is skipped while nothing changes")
    func ignoredWriteIsSkipped() {
        let manager = MenuBarItemManager()
        let item = makeItem()
        manager.noteIgnoredPreferredWrite(for: item)

        #expect(!manager.revealRepairMoves(item, isMisplaced: true))
        #expect(!manager.revealRepairMoves(item, isMisplaced: true, logging: false), "The next reveal skips it too")
    }

    @Test("An item whose frame changed after an ignored write is tried again")
    func changedFrameIsRetried() {
        let manager = MenuBarItemManager()
        manager.noteIgnoredPreferredWrite(for: makeItem(x: 1000))

        #expect(manager.revealRepairMoves(makeItem(x: 1100), isMisplaced: true))
        #expect(manager.revealRepairMoves(makeItem(x: 1000), isMisplaced: true), "The changed frame cleared the note")
    }

    @Test("An ignored write skips only that item")
    func ignoredWriteIsPerItem() {
        let manager = MenuBarItemManager()
        manager.noteIgnoredPreferredWrite(for: makeItem(title: "Ignored"))

        #expect(manager.revealRepairMoves(makeItem(title: "Other"), isMisplaced: true))
    }

    @Test("Ignored writes count against the move breaker")
    func ignoredWritesTripTheBreaker() {
        let manager = MenuBarItemManager()
        let item = makeItem()
        for _ in 0 ..< 8 {
            manager.noteIgnoredPreferredWrite(for: item)
        }
        #expect(!manager.moveCircuitBreaker.isOpen)

        manager.noteIgnoredPreferredWrite(for: item)
        #expect(manager.moveCircuitBreaker.isOpen)
    }

    @Test("Without a running menu bar, a reveal does not leave the order to macOS")
    func noMenuBarKeepsOrdering() {
        let manager = MenuBarItemManager()
        #expect(!manager.revealLeavesOrderToMacOS(.hidden, items: [makeItem()]))
    }

    @Test("Preparing a reveal before setup writes nothing")
    func prepareBeforeSetupWritesNothing() {
        let manager = MenuBarItemManager()
        let generation = manager.repairs.writeGeneration

        manager.prepareReveal(cause: .revealHideTransition)

        #expect(manager.repairs.writeGeneration == generation)
    }
}

@MainActor
@Suite("Native hiding reveal")
struct NativeRevealStartTests {
    @Test("A reveal remembers the apps Native hiding had switched off")
    func firstRevealRecordsHiddenApps() {
        let experiment = NativeAppHidingExperiment()
        experiment.noteRevealStarting(hiddenBundleIDs: ["com.example.a", "com.example.b"], alreadyRevealed: false)

        #expect(experiment.switchedOnForReveal == ["com.example.a", "com.example.b"])
    }

    @Test("Widening a reveal already on screen keeps the apps the first one switched on")
    func wideningRevealKeepsEarlierApps() {
        let experiment = NativeAppHidingExperiment()
        experiment.noteRevealStarting(hiddenBundleIDs: ["com.example.a"], alreadyRevealed: false)
        experiment.noteRevealStarting(hiddenBundleIDs: ["com.example.b"], alreadyRevealed: true)

        #expect(experiment.switchedOnForReveal == ["com.example.a", "com.example.b"])
    }

    @Test("A new reveal forgets the apps an earlier one switched on")
    func newRevealStartsOver() {
        let experiment = NativeAppHidingExperiment()
        experiment.noteRevealStarting(hiddenBundleIDs: ["com.example.a"], alreadyRevealed: false)
        experiment.noteRevealStarting(hiddenBundleIDs: ["com.example.b"], alreadyRevealed: false)

        #expect(experiment.switchedOnForReveal == ["com.example.b"])
    }

    @Test("A reveal with nothing hidden switches nothing on")
    func nothingHidden() {
        let experiment = NativeAppHidingExperiment()
        experiment.noteRevealStarting(hiddenBundleIDs: [], alreadyRevealed: false)

        #expect(experiment.switchedOnForReveal.isEmpty)
    }

    @Test("While Native isn't running, nothing blocks a reveal for a picture")
    func inactiveNativeAllowsCaptureReveal() {
        let experiment = NativeAppHidingExperiment()

        #expect(!experiment.isActive)
        #expect(!experiment.blocksCaptureReveal)
    }
}
