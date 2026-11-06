//
//  ReadOnlyPositionStoreSeatingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import PlatformRuntimeKit
import Testing
@testable import Thaw

/// ReadOnlyPositionStore is what makes manual arrangement structural: a
/// caller that has never heard of the setting still cannot reorder the bar.
/// Its one permitted write places Thaw's own control items, because those are
/// the section boundary and hiding needs them.
///
/// Forwarding that write to the live store would lay a fresh ladder over the
/// whole desired order, rewriting every member's weight on each reveal while
/// the same session refuses every move the user makes.
@MainActor
@Suite("Manual arrangement seats controls without moving members")
struct ReadOnlyPositionStoreSeatingTests {
    /// Descending axis, as measured on the release candidate: lower weight
    /// sorts further right. Members are 100 apart, hidden band on the left.
    private static func makeBar() -> (items: [MenuBarItem], positions: [String: Int]) {
        let tailscale = member("io.tailscale.ipn.macsys", "Item-0", windowID: 1, x: 100)
        let shottr = member("cc.ffitch.shottr", "Item-0", windowID: 2, x: 140)
        let divider = control(tag: .hiddenControlItem, windowID: 3, x: 180)
        let drive = member("ch.protonmail.drive", "Proton Drive", windowID: 4, x: 220)
        let chevron = control(tag: .visibleControlItem, windowID: 5, x: 260)

        let positions: [String: Int] = [
            key(tailscale): -5000,
            key(shottr): -5100,
            key(divider): -5150,
            key(drive): -5200,
            key(chevron): -5300,
        ]
        return ([tailscale, shottr, divider, drive, chevron], positions)
    }

    @Test("A member's weight is never written")
    func membersAreNeverWritten() {
        let (items, positions) = Self.makeBar()
        // Both controls start on the wrong side of every member.
        var damaged = positions
        damaged[Self.key(items[2])] = -4000
        damaged[Self.key(items[4])] = -4100
        let base = FakeStore(positions: damaged)
        let store = ReadOnlyPositionStore(wrapping: base)

        let changed = store.applyControlItemOrder(
            desiredOrder: items,
            opaqueVisibleKeys: [],
            liveItems: items
        )

        #expect(!changed.isEmpty, "the misplaced controls were not seated")
        for member in [items[0], items[1], items[3]] {
            #expect(
                base.positions[Self.key(member)] == positions[Self.key(member)],
                "\(member.logString) was rewritten to \(String(describing: base.positions[Self.key(member)]))"
            )
        }
    }

    @Test("Each control lands between its neighbours in the desired order")
    func controlsLandBetweenTheirNeighbours() throws {
        let (items, positions) = Self.makeBar()
        var damaged = positions
        damaged[Self.key(items[2])] = -4000
        let base = FakeStore(positions: damaged)
        let store = ReadOnlyPositionStore(wrapping: base)

        _ = store.applyControlItemOrder(desiredOrder: items, opaqueVisibleKeys: [], liveItems: items)

        let seated = try #require(base.positions[Self.key(items[2])])
        let shottr = try #require(base.positions[Self.key(items[1])])
        let drive = try #require(base.positions[Self.key(items[3])])
        #expect(
            seated < shottr && seated > drive,
            "divider at \(seated) is not between \(shottr) and \(drive)"
        )
    }

    @Test("A bar that is already right writes nothing")
    func aSettledBarWritesNothing() {
        let (items, positions) = Self.makeBar()
        let base = FakeStore(positions: positions)
        let store = ReadOnlyPositionStore(wrapping: base)

        let changed = store.applyControlItemOrder(
            desiredOrder: items,
            opaqueVisibleKeys: [],
            liveItems: items
        )

        #expect(changed.isEmpty, "a settled ladder was rewritten: \(changed)")
        #expect(base.writeCount == 0)
        #expect(base.positions == positions)
    }

    @Test("With no weight free between its neighbours the control keeps its slot")
    func aFullGapLeavesTheControlAlone() {
        let tailscale = Self.member("io.tailscale.ipn.macsys", "Item-0", windowID: 1, x: 100)
        let divider = Self.control(tag: .hiddenControlItem, windowID: 2, x: 140)
        let drive = Self.member("ch.protonmail.drive", "Proton Drive", windowID: 3, x: 180)
        // Adjacent integers: nothing sorts between them.
        let positions: [String: Int] = [
            Self.key(tailscale): -5000,
            Self.key(divider): -4000,
            Self.key(drive): -5001,
        ]
        let base = FakeStore(positions: positions)
        let store = ReadOnlyPositionStore(wrapping: base)

        let changed = store.applyControlItemOrder(
            desiredOrder: [tailscale, divider, drive],
            opaqueVisibleKeys: [],
            liveItems: [tailscale, divider, drive]
        )

        #expect(changed.isEmpty)
        #expect(base.positions[Self.key(divider)] == -4000, "the control was moved into an occupied gap")
    }

    @Test("An ascending table seats the control the other way round")
    func ascendingAxisIsHonoured() throws {
        let tailscale = Self.member("io.tailscale.ipn.macsys", "Item-0", windowID: 1, x: 100)
        let divider = Self.control(tag: .hiddenControlItem, windowID: 2, x: 140)
        let drive = Self.member("ch.protonmail.drive", "Proton Drive", windowID: 3, x: 180)
        let positions: [String: Int] = [
            Self.key(tailscale): 5000,
            Self.key(divider): 9000,
            Self.key(drive): 5200,
        ]
        let base = FakeStore(positions: positions)
        let store = ReadOnlyPositionStore(wrapping: base)

        _ = store.applyControlItemOrder(
            desiredOrder: [tailscale, divider, drive],
            opaqueVisibleKeys: [],
            liveItems: [tailscale, divider, drive]
        )

        let seated = try #require(base.positions[Self.key(divider)])
        #expect(seated > 5000 && seated < 5200, "divider at \(seated) is not between 5000 and 5200")
        #expect(base.positions[Self.key(tailscale)] == 5000)
        #expect(base.positions[Self.key(drive)] == 5200)
    }

    @Test("Conflicting fixed anchors do not rewrite controls on repeated reveals")
    func conflictingAnchorsWriteNothing() {
        let (items, positions) = Self.makeBar()
        let base = FakeStore(positions: positions)
        let store = ReadOnlyPositionStore(wrapping: base)
        // The saved order disagrees with the live descending axis. Seating
        // the divider between Drive and Shottr cannot satisfy that order
        // without moving a member, which manual arrangement forbids.
        let desiredOrder = [items[0], items[3], items[2], items[1], items[4]]

        for _ in 0 ..< 3 {
            let changed = store.applyControlItemOrder(
                desiredOrder: desiredOrder,
                opaqueVisibleKeys: [],
                liveItems: items
            )
            #expect(changed.isEmpty)
        }
        #expect(base.writeCount == 0)
        #expect(base.positions == positions)
    }

    // MARK: Fixtures

    private static func key(_ item: MenuBarItem) -> String {
        RuntimePreferenceKeys.naiveKey(for: item)
    }

    private static func member(
        _ bundleID: String,
        _ title: String,
        windowID: CGWindowID,
        x: CGFloat
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: title, instanceIndex: 0),
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static func control(
        tag: MenuBarItemTag,
        windowID: CGWindowID,
        x: CGFloat
    ) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: x, y: 0, width: 2, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }
}

/// The live store stands in as a dictionary. Only the reads and the raw write
/// are exercised; every ordering call would be refused by the wrapper anyway.
@MainActor
private final class FakeStore: MenuBarPositionStoring {
    private(set) var positions: [String: Int]
    private(set) var writeCount = 0

    init(positions: [String: Int]) {
        self.positions = positions
    }

    func currentPositions() -> [String: Int] {
        positions
    }

    func readPositions() -> [String: Int] {
        positions
    }

    func positionsDomainIsAccessible() -> Bool {
        true
    }

    func resolveKey(
        for item: MenuBarItem,
        existingKeys: [String],
        positions _: [String: Int],
        liveItems _: [MenuBarItem]
    ) -> String? {
        let key = RuntimePreferenceKeys.naiveKey(for: item)
        return existingKeys.contains(key) ? key : nil
    }

    func parseStatusKey(_: String) -> PositionStatusKey? {
        nil
    }

    func isParkedWeight(_: Int) -> Bool {
        false
    }

    @discardableResult
    func move(
        item _: MenuBarItem,
        to _: MoveDestination,
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> Bool {
        false
    }

    func applyOrder(
        desiredOrder _: [String],
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> [String] {
        []
    }

    func respaceOrder(
        desiredOrder _: [String],
        liveItems _: [MenuBarItem],
        experimentalSystemItemHiding _: Bool
    ) -> [String] {
        []
    }

    func breakTiedSiblingWeights(liveItems _: [MenuBarItem]) -> [String] {
        []
    }

    func applyControlItemOrder(
        desiredOrder _: [MenuBarItem],
        opaqueVisibleKeys _: [String],
        liveItems _: [MenuBarItem]
    ) -> [String] {
        Issue.record("the wrapper forwarded to the live store instead of seating the controls itself")
        return []
    }

    func writePositions(_ positions: [String: Int]) {
        self.positions = positions
        writeCount += 1
    }

    func isProvenAbsent(_: String) -> Bool {
        false
    }

    @discardableResult
    func recordAbsenceEvidence(seen _: Set<String>, blank _: Set<String>) -> Set<String> {
        []
    }

    func resetAbsenceEvidence() {}
}
