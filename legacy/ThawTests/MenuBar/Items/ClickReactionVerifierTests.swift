//
//  ClickReactionVerifierTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Covers the two rules that decide whether an owner reacted to a click.
///
/// The mistakes to guard against: crediting an unrelated app's window, or
/// reading an item's ordinary reflow as a reaction.
///
/// Serialized because overlapping CGS window-list calls on `Bridging`'s
/// process-wide main connection are not safe.
@Suite("Click reaction verifier", .serialized)
struct ClickReactionVerifierTests {
    private let ownerPID: pid_t = 501
    private let helperPID: pid_t = 502
    private let strangerPID: pid_t = 999

    private func window(
        _ windowID: CGWindowID,
        pid: pid_t,
        layer: Int = 0
    ) -> WindowInfo {
        WindowInfo(windowID: windowID, ownerPID: pid, bounds: .zero, layer: layer)
    }

    private var menuLayer: Int {
        Int(CGWindowLevelForKey(.popUpMenuWindow))
    }

    // MARK: Interface window

    @Test("No new windows means no interface opened")
    func noNewWindowsMeansNoInterface() {
        #expect(ClickReactionVerifier.interfaceWindow(among: [], ownedBy: [ownerPID]) == nil)
    }

    @Test("Another app's window is not a reaction")
    func anotherAppsWindowIsNotAReaction() {
        // The user's mail client opening a notification while we clicked
        // says nothing about the item we clicked.
        let candidates = [window(1, pid: strangerPID, layer: menuLayer)]

        #expect(ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID]) == nil)
    }

    @Test("The owner's own window is a reaction")
    func theOwnersWindowIsAReaction() {
        let candidates = [window(1, pid: ownerPID, layer: menuLayer)]

        #expect(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID
                == 1
        )
    }

    @Test("A helper-hosted item counts through its source PID")
    func aHelperHostedItemCountsThroughItsSourcePID() {
        // An item's window and the process that reacts to it are not
        // always the same, which is why the snapshot carries both.
        let candidates = [window(1, pid: helperPID, layer: menuLayer)]

        #expect(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID, helperPID])?.windowID
                == 1
        )
    }

    @Test("A menu window is preferred over the owner's other windows")
    func aMenuWindowIsPreferredOverTheOwnersOtherWindows() {
        let candidates = [
            window(1, pid: ownerPID, layer: 0),
            window(2, pid: ownerPID, layer: menuLayer),
        ]

        #expect(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID
                == 2
        )
    }

    @Test("A non-menu window still counts when it is all the owner opened")
    func aNonMenuWindowStillCountsWhenItIsAllTheOwnerOpened() {
        // A popover or panel is weaker evidence than a menu, but it is
        // still the owner doing something in response to the click.
        let candidates = [window(7, pid: ownerPID, layer: 0)]

        #expect(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID
                == 7
        )
    }

    @Test("The owner's window wins over a stranger's menu")
    func theOwnersWindowWinsOverAStrangersMenu() {
        let candidates = [
            window(1, pid: strangerPID, layer: menuLayer),
            window(2, pid: ownerPID, layer: 0),
        ]

        #expect(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID
                == 2
        )
    }

    // MARK: Item change

    @Test("An item window that vanished is a reaction")
    func aVanishedItemWindowIsAReaction() {
        #expect(ClickReactionVerifier.itemChanged(from: CGRect(x: 100, y: 0, width: 24, height: 24), to: nil))
    }

    @Test("An unchanged item is not a reaction")
    func anUnchangedItemIsNotAReaction() {
        let bounds = CGRect(x: 100, y: 0, width: 24, height: 24)

        #expect(!ClickReactionVerifier.itemChanged(from: bounds, to: bounds))
    }

    @Test("An item that only moved is not a reaction")
    func anItemThatOnlyMovedIsNotAReaction() {
        // Items slide sideways whenever a neighbor appears or the menu bar
        // reflows, which is not a reaction.
        let before = CGRect(x: 100, y: 0, width: 24, height: 24)
        let after = CGRect(x: 340, y: 0, width: 24, height: 24)

        #expect(!ClickReactionVerifier.itemChanged(from: before, to: after))
    }

    @Test("An item that grew wider is a reaction")
    func aWiderItemIsAReaction() {
        let before = CGRect(x: 100, y: 0, width: 24, height: 24)
        let after = CGRect(x: 100, y: 0, width: 48, height: 24)

        #expect(ClickReactionVerifier.itemChanged(from: before, to: after))
    }

    @Test("Sub-point differences are rounding, not reactions")
    func subPointDifferencesAreRoundingNotReactions() {
        let before = CGRect(x: 100, y: 0, width: 24, height: 24)
        let after = CGRect(x: 100, y: 0, width: 24.5, height: 24.5)

        #expect(!ClickReactionVerifier.itemChanged(from: before, to: after))
    }

    // MARK: Reaction

    @Test("Only an unobserved reaction means nothing happened")
    func onlyUnobservedMeansNoReaction() {
        #expect(!ClickReactionVerifier.Reaction.unobserved.didReact)
        #expect(ClickReactionVerifier.Reaction.itemChanged.didReact)
        #expect(ClickReactionVerifier.Reaction.openedInterface(1).didReact)
    }

    @Test("Only an opened interface carries a window identifier")
    func onlyAnOpenedInterfaceCarriesAWindow() {
        #expect(ClickReactionVerifier.Reaction.openedInterface(42).openedWindowID == 42)
        #expect(ClickReactionVerifier.Reaction.itemChanged.openedWindowID == nil)
        #expect(ClickReactionVerifier.Reaction.unobserved.openedWindowID == nil)
    }

    // MARK: Snapshot

    @Test("A snapshot carries both processes that could react")
    func snapshotCarriesBothProcessesThatCouldReact() {
        // For helper-hosted items a reaction from either process counts.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.helper", title: "Status"),
            windowID: 77,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            sourcePID: helperPID,
            ownerPID: ownerPID
        )

        let snapshot = ClickReactionVerifier.snapshot(for: item)

        #expect(snapshot.pids == [ownerPID, helperPID])
        #expect(snapshot.itemWindowID == 77)
        #expect(snapshot.itemBounds == item.bounds)
    }

    @Test("A snapshot of an item with no source keeps only its owner")
    func snapshotOfAnItemWithNoSourceKeepsOnlyItsOwner() {
        // Control items have no source PID. The compactMap must drop it
        // rather than admitting a bogus entry that could credit a stranger.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 78,
            sourcePID: nil,
            ownerPID: ownerPID
        )

        let snapshot = ClickReactionVerifier.snapshot(for: item)

        #expect(snapshot.pids == [ownerPID])
    }

    @Test("A snapshot records the windows already on screen")
    func snapshotRecordsTheWindowsAlreadyOnScreen() {
        // Windows open at snapshot time must not later be mistaken for
        // ones the click opened.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 79
        )

        let snapshot = ClickReactionVerifier.snapshot(for: item)

        #expect(!snapshot.onScreenWindowIDs.isEmpty)
    }

    // MARK: Verification

    @Test("An item window that was never on screen is not a reaction")
    func anItemWindowThatWasNeverOnScreenIsNotAReaction() async {
        // A window ID unknown to both the window server and the snapshot is
        // stale, not an item that removed itself in response to the click.
        let snapshot = ClickReactionVerifier.Snapshot(
            pids: [ownerPID],
            itemWindowID: .max,
            itemBounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            onScreenWindowIDs: Set(Bridging.getWindowList(option: .onScreen))
        )

        let reaction = await ClickReactionVerifier.verify(against: snapshot)

        #expect(reaction == .unobserved)
        #expect(!reaction.didReact)
    }
}
