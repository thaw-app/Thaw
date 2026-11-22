//
//  ClickReactionVerifierTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Waiting for an owner's reaction, against snapshots of windows that don't exist.
@Suite("Click reaction verifier")
struct ClickReactionVerifierTests {
    /// A window ID the window server has not handed out.
    private let missingWindowID = CGWindowID(UInt32.max - 7)

    private func snapshot(itemWindowWasOnScreen: Bool) -> ClickReactionVerifier.Snapshot {
        ClickReactionVerifier.Snapshot(
            pids: [],
            itemWindowID: missingWindowID,
            itemBounds: CGRect(x: 0, y: 0, width: 30, height: 24),
            itemWindowWasOnScreen: itemWindowWasOnScreen,
            onScreenWindowIDs: Set(Bridging.getWindowList(option: .onScreen))
        )
    }

    @Test("An item window that was on screen and is gone counts as the owner acting, at once")
    func goneWindowReacts() async {
        let started = ContinuousClock.now
        let reaction = await ClickReactionVerifier.verifyAllowingLateOpen(against: snapshot(itemWindowWasOnScreen: true))
        #expect(reaction == .itemChanged)
        #expect(reaction.didReact)
        // A reaction skips the late wait.
        #expect(ContinuousClock.now - started < ClickReactionVerifier.lateBudget)
    }

    @Test("With nothing to watch, the wait runs out on both budgets and reports nothing")
    func nothingObserved() async {
        let started = ContinuousClock.now
        let reaction = await ClickReactionVerifier.verifyAllowingLateOpen(against: snapshot(itemWindowWasOnScreen: false))
        #expect(reaction == .unobserved)
        #expect(!reaction.didReact)
        #expect(ContinuousClock.now - started >= ClickReactionVerifier.lateBudget)
    }

    @Test("A cancelled wait reports nothing")
    func cancelledWait() async {
        let task = Task {
            await ClickReactionVerifier.verify(against: snapshot(itemWindowWasOnScreen: false), budget: .seconds(5))
        }
        task.cancel()
        #expect(await task.value == .unobserved)
    }

    private func window(_ windowID: CGWindowID, pid: pid_t, layer: Int) -> WindowInfo {
        WindowInfo(windowID: windowID, ownerPID: pid, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), layer: layer)
    }

    @Test("Of the new windows, a menu-level one owned by the item's processes is preferred")
    func menuWindowIsPreferred() {
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let candidates = [window(1, pid: 50, layer: menuLevel), window(2, pid: 10, layer: 0), window(3, pid: 10, layer: menuLevel)]
        #expect(ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [10])?.windowID == 3)
    }

    @Test("Without a menu-level window, the first new window of an owner still counts")
    func anyOwnedWindowCounts() {
        let candidates = [window(1, pid: 50, layer: 0), window(2, pid: 10, layer: 3), window(4, pid: 11, layer: 3)]
        #expect(ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [10, 11])?.windowID == 2)
    }

    @Test("New windows of other processes are no reaction")
    func foreignWindowsDoNotCount() {
        let candidates = [window(1, pid: 50, layer: Int(CGWindowLevelForKey(.popUpMenuWindow)))]
        #expect(ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [10]) == nil)
        #expect(ClickReactionVerifier.interfaceWindow(among: [], ownedBy: [10]) == nil)
    }
}

@Suite("Click reactions are judged by the item's size and its owners")
struct ClickReactionDecisionTests {
    private let before = CGRect(x: 100, y: 0, width: 30, height: 24)

    @Test("A vanished window is a change")
    func vanishedWindowChanged() {
        #expect(ClickReactionVerifier.itemChanged(from: before, to: nil))
    }

    @Test("A moved window of the same size is not a change")
    func movedIsNotChanged() {
        #expect(!ClickReactionVerifier.itemChanged(from: before, to: before.offsetBy(dx: 40, dy: 0)))
    }

    @Test("A wider or taller window is a change")
    func resizedIsChanged() {
        #expect(ClickReactionVerifier.itemChanged(from: before, to: CGRect(x: 100, y: 0, width: 60, height: 24)))
        #expect(ClickReactionVerifier.itemChanged(from: before, to: CGRect(x: 100, y: 0, width: 30, height: 40)))
    }

    @Test("Reaction owners are the owner and, when different, the source")
    func reactionPIDs() {
        let hosted = ItemsFixture.item("A", bundle: "com.example.react", windowID: 4, ownerPID: 10, sourcePID: 20)
        let own = ItemsFixture.item("A", bundle: "com.example.react", windowID: 5, ownerPID: 10, sourcePID: nil)
        #expect(hosted.reactionPIDs == [10, 20])
        #expect(own.reactionPIDs == [10])
    }

    /// An item whose window does not exist.
    private let missing = ItemsFixture.item(
        "B", bundle: "com.example.react", x: 100, windowID: CGWindowID(UInt32.max - 11), ownerPID: 999_975, sourcePID: 999_976
    )

    @Test("A snapshot of an item whose window does not exist records it as off screen")
    func snapshotOfMissingWindow() {
        let snapshot = ClickReactionVerifier.snapshot(for: missing)

        #expect(snapshot.pids == [999_975, 999_976])
        #expect(snapshot.itemWindowID == missing.windowID)
        #expect(snapshot.itemBounds == missing.bounds)
        #expect(!snapshot.itemWindowWasOnScreen)
        #expect(!snapshot.onScreenWindowIDs.contains(missing.windowID))
    }

    @Test("A snapshot also watches the process a press found the element in, when there is one")
    func snapshotAlsoWatchesThePressedProcess() {
        #expect(ClickReactionVerifier.snapshot(for: missing, alsoWatching: 999_977).pids == [999_975, 999_976, 999_977])
        #expect(ClickReactionVerifier.snapshot(for: missing, alsoWatching: 0).pids == [999_975, 999_976])
    }
}
