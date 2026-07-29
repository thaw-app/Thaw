//
//  ClickReactionVerifierTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

/// Covers the two rules that decide whether an owner reacted to a click.
///
/// The polling loop around them talks to the window server and cannot run
/// here, but the rules themselves are where the mistakes live: crediting
/// an unrelated app's window, or reading an item's ordinary reflow as a
/// reaction.
final class ClickReactionVerifierTests: XCTestCase {
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

    func testNoNewWindowsMeansNoInterface() {
        XCTAssertNil(ClickReactionVerifier.interfaceWindow(among: [], ownedBy: [ownerPID]))
    }

    func testAnotherAppsWindowIsNotAReaction() {
        // The user's mail client opening a notification while we clicked
        // says nothing about the item we clicked.
        let candidates = [window(1, pid: strangerPID, layer: menuLayer)]

        XCTAssertNil(ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID]))
    }

    func testTheOwnersWindowIsAReaction() {
        let candidates = [window(1, pid: ownerPID, layer: menuLayer)]

        XCTAssertEqual(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID,
            1
        )
    }

    func testAHelperHostedItemCountsThroughItsSourcePID() {
        // An item's window and the process that reacts to it are not
        // always the same, which is why the snapshot carries both.
        let candidates = [window(1, pid: helperPID, layer: menuLayer)]

        XCTAssertEqual(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID, helperPID])?.windowID,
            1
        )
    }

    func testAMenuWindowIsPreferredOverTheOwnersOtherWindows() {
        let candidates = [
            window(1, pid: ownerPID, layer: 0),
            window(2, pid: ownerPID, layer: menuLayer),
        ]

        XCTAssertEqual(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID,
            2
        )
    }

    func testANonMenuWindowStillCountsWhenItIsAllTheOwnerOpened() {
        // A popover or panel is weaker evidence than a menu, but it is
        // still the owner doing something in response to the click.
        let candidates = [window(7, pid: ownerPID, layer: 0)]

        XCTAssertEqual(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID,
            7
        )
    }

    func testTheOwnersWindowWinsOverAStrangersMenu() {
        let candidates = [
            window(1, pid: strangerPID, layer: menuLayer),
            window(2, pid: ownerPID, layer: 0),
        ]

        XCTAssertEqual(
            ClickReactionVerifier.interfaceWindow(among: candidates, ownedBy: [ownerPID])?.windowID,
            2
        )
    }

    // MARK: Item change

    func testAVanishedItemWindowIsAReaction() {
        XCTAssertTrue(ClickReactionVerifier.itemChanged(from: CGRect(x: 100, y: 0, width: 24, height: 24), to: nil))
    }

    func testAnUnchangedItemIsNotAReaction() {
        let bounds = CGRect(x: 100, y: 0, width: 24, height: 24)

        XCTAssertFalse(ClickReactionVerifier.itemChanged(from: bounds, to: bounds))
    }

    func testAnItemThatOnlyMovedIsNotAReaction() {
        // Items slide sideways whenever a neighbor appears or the menu bar
        // reflows. Treating that as a reaction would credit every click
        // made while anything else on the menu bar changed.
        let before = CGRect(x: 100, y: 0, width: 24, height: 24)
        let after = CGRect(x: 340, y: 0, width: 24, height: 24)

        XCTAssertFalse(ClickReactionVerifier.itemChanged(from: before, to: after))
    }

    func testAWiderItemIsAReaction() {
        let before = CGRect(x: 100, y: 0, width: 24, height: 24)
        let after = CGRect(x: 100, y: 0, width: 48, height: 24)

        XCTAssertTrue(ClickReactionVerifier.itemChanged(from: before, to: after))
    }

    func testSubPointDifferencesAreRoundingNotReactions() {
        let before = CGRect(x: 100, y: 0, width: 24, height: 24)
        let after = CGRect(x: 100, y: 0, width: 24.5, height: 24.5)

        XCTAssertFalse(ClickReactionVerifier.itemChanged(from: before, to: after))
    }

    // MARK: Reaction

    func testOnlyUnobservedMeansNoReaction() {
        XCTAssertFalse(ClickReactionVerifier.Reaction.unobserved.didReact)
        XCTAssertTrue(ClickReactionVerifier.Reaction.itemChanged.didReact)
        XCTAssertTrue(ClickReactionVerifier.Reaction.openedInterface(1).didReact)
    }

    func testOnlyAnOpenedInterfaceCarriesAWindow() {
        XCTAssertEqual(ClickReactionVerifier.Reaction.openedInterface(42).openedWindowID, 42)
        XCTAssertNil(ClickReactionVerifier.Reaction.itemChanged.openedWindowID)
        XCTAssertNil(ClickReactionVerifier.Reaction.unobserved.openedWindowID)
    }

    // MARK: Snapshot

    func testSnapshotCarriesBothProcessesThatCouldReact() {
        // Helper-hosted items are common: the window belongs to one process
        // and the app that reacts is another, so a reaction from either
        // counts.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.helper", title: "Status"),
            windowID: 77,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            sourcePID: helperPID,
            ownerPID: ownerPID
        )

        let snapshot = ClickReactionVerifier.snapshot(for: item)

        XCTAssertEqual(snapshot.pids, [ownerPID, helperPID])
        XCTAssertEqual(snapshot.itemWindowID, 77)
        XCTAssertEqual(snapshot.itemBounds, item.bounds)
    }

    func testSnapshotOfAnItemWithNoSourceKeepsOnlyItsOwner() {
        // Control items have no source PID. The compactMap must drop it
        // rather than admitting a bogus entry that could credit a stranger.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 78,
            sourcePID: nil,
            ownerPID: ownerPID
        )

        let snapshot = ClickReactionVerifier.snapshot(for: item)

        XCTAssertEqual(snapshot.pids, [ownerPID])
    }

    func testSnapshotRecordsTheWindowsAlreadyOnScreen() {
        // Windows open at snapshot time must not later be mistaken for
        // ones the click opened. The test host itself is running, so the
        // window server always has something to report here.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 79
        )

        let snapshot = ClickReactionVerifier.snapshot(for: item)

        XCTAssertFalse(snapshot.onScreenWindowIDs.isEmpty)
    }

    // MARK: Verification

    func testAnItemWindowThatIsNotOnScreenReadsAsAReaction() async {
        // The verifier is asked about a window ID the window server does
        // not know, which is the same observation as an item that removed
        // itself in response to the click. It has to resolve on the first
        // look rather than spending the whole budget.
        let snapshot = ClickReactionVerifier.Snapshot(
            pids: [ownerPID],
            itemWindowID: .max,
            itemBounds: CGRect(x: 100, y: 0, width: 24, height: 24),
            onScreenWindowIDs: Set(Bridging.getWindowList(option: .onScreen))
        )

        let reaction = await ClickReactionVerifier.verify(against: snapshot)

        XCTAssertEqual(reaction, .itemChanged)
        XCTAssertTrue(reaction.didReact)
    }
}
