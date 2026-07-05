//
//  MenuBarAgentPositionStoreTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@available(macOS 27, *)
@MainActor
final class MenuBarAgentPositionStoreTests: XCTestCase {
    // MARK: - midpointPosition

    func testMidpointReturnsValueBetweenNeighbors() {
        XCTAssertEqual(MenuBarAgentPositionStore.midpointPosition(between: 100, and: 200), 150)
    }

    func testMidpointIsOrderAgnostic() {
        // Same result regardless of which bound is larger.
        XCTAssertEqual(
            MenuBarAgentPositionStore.midpointPosition(between: 200, and: 100),
            MenuBarAgentPositionStore.midpointPosition(between: 100, and: 200)
        )
    }

    func testMidpointNilWhenNoIntegerGap() {
        XCTAssertNil(MenuBarAgentPositionStore.midpointPosition(between: 100, and: 101))
        XCTAssertNil(MenuBarAgentPositionStore.midpointPosition(between: 100, and: 100))
    }

    // MARK: - resolveKey

    func testResolveModuleKey() {
        let item = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .menuBarAgent, title: "WiFi"),
            windowID: 1
        )
        XCTAssertEqual(
            MenuBarAgentPositionStore.resolveKey(for: item, existingKeys: ["module:WiFi", "module:Clock"]),
            "module:WiFi"
        )
    }

    func testResolveStatusKeyByBundleIDForm() {
        // The common form is status:<bundleID>::<itemID>, and the bundleID is
        // the item's namespace. Many apps share the generic "Item-0" title, so
        // the exact bundle-ID key must win over the ambiguous suffix match.
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "notion.id", title: "Item-0"),
            windowID: 2
        )
        XCTAssertEqual(
            MenuBarAgentPositionStore.resolveKey(
                for: item,
                existingKeys: [
                    "status:notion.id::Item-0",
                    "status:cc.ffitch.shottr::Item-0",
                    "status:com.anthropic.claudefordesktop::Item-0",
                ]
            ),
            "status:notion.id::Item-0"
        )
    }

    func testResolveStatusKeyBySuffix() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.foo.Bar", title: "Item-0"),
            windowID: 2
        )
        XCTAssertEqual(
            MenuBarAgentPositionStore.resolveKey(
                for: item,
                existingKeys: ["status:Bar::Item-0", "status:Other::Item-9"]
            ),
            "status:Bar::Item-0"
        )
    }

    func testResolveReturnsNilWhenAbsent() {
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.foo.Bar", title: "Ghost"),
            windowID: 3
        )
        XCTAssertNil(
            MenuBarAgentPositionStore.resolveKey(for: item, existingKeys: ["status:Bar::Item-0"])
        )
    }

    func testResolvePositionalKeyPairsSiblingsByXAndWeightWhenTitlesNeverMatch() {
        // iStat-style family: three sibling items whose live titles ("CPU 9%",
        // "MEM 51%", "12.3 KB/s") never match the keys MenuBarAgent stores them
        // under (the autosaveName, not the title). The family's key count
        // matches its item count, so position pairs them up.
        let cpu = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "CPU 9%"),
            windowID: 10,
            bounds: CGRect(x: 0, y: 0, width: 40, height: 22)
        )
        let mem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "MEM 51%"),
            windowID: 11,
            bounds: CGRect(x: 50, y: 0, width: 40, height: 22)
        )
        let net = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "12.3 KB/s"),
            windowID: 12,
            bounds: CGRect(x: 100, y: 0, width: 40, height: 22)
        )
        let positions = [
            "status:com.bjango.istatmenus::com.bjango.istatmenus.cpu": 100,
            "status:com.bjango.istatmenus::com.bjango.istatmenus.memory": 200,
            "status:com.bjango.istatmenus::com.bjango.istatmenus.network": 300,
        ]

        XCTAssertEqual(
            MenuBarAgentPositionStore.resolveKey(
                for: cpu,
                existingKeys: Array(positions.keys),
                positions: positions,
                liveItems: [cpu, mem, net]
            ),
            "status:com.bjango.istatmenus::com.bjango.istatmenus.cpu"
        )
        XCTAssertEqual(
            MenuBarAgentPositionStore.resolveKey(
                for: net,
                existingKeys: Array(positions.keys),
                positions: positions,
                liveItems: [cpu, mem, net]
            ),
            "status:com.bjango.istatmenus::com.bjango.istatmenus.network"
        )
    }

    func testResolvePositionalKeyInfersDescendingAxisFromUnrelatedReferenceItems() {
        // Same iStat-style family as above, but this bar's weight axis
        // descends left-to-right (unlike the ascending default). Two
        // unrelated, title-resolvable reference items elsewhere in the bar
        // carry the only evidence of that: the left one has the larger
        // weight, the right one the smaller. Resolution must read the axis
        // from those references rather than assuming ascending, or it pairs
        // every sibling in this family backwards.
        let referenceLeft = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.foo.Left", title: "Marker"),
            windowID: 20,
            bounds: CGRect(x: 0, y: 0, width: 40, height: 22)
        )
        let referenceRight = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.foo.Right", title: "Marker"),
            windowID: 21,
            bounds: CGRect(x: 200, y: 0, width: 40, height: 22)
        )
        let cpu = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "CPU 9%"),
            windowID: 10,
            bounds: CGRect(x: 50, y: 0, width: 40, height: 22)
        )
        let mem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "MEM 51%"),
            windowID: 11,
            bounds: CGRect(x: 100, y: 0, width: 40, height: 22)
        )
        let net = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "12.3 KB/s"),
            windowID: 12,
            bounds: CGRect(x: 150, y: 0, width: 40, height: 22)
        )
        let positions = [
            "status:com.foo.Left::Marker": 300,
            "status:com.foo.Right::Marker": 100,
            "status:com.bjango.istatmenus::com.bjango.istatmenus.cpu": 50,
            "status:com.bjango.istatmenus::com.bjango.istatmenus.memory": 30,
            "status:com.bjango.istatmenus::com.bjango.istatmenus.network": 10,
        ]
        let liveItems = [referenceLeft, cpu, mem, net, referenceRight]

        XCTAssertEqual(
            MenuBarAgentPositionStore.resolveKey(
                for: cpu,
                existingKeys: Array(positions.keys),
                positions: positions,
                liveItems: liveItems
            ),
            "status:com.bjango.istatmenus::com.bjango.istatmenus.cpu"
        )
        XCTAssertEqual(
            MenuBarAgentPositionStore.resolveKey(
                for: net,
                existingKeys: Array(positions.keys),
                positions: positions,
                liveItems: liveItems
            ),
            "status:com.bjango.istatmenus::com.bjango.istatmenus.network"
        )
    }

    func testResolvePositionalKeyNilWhenFamilyCountMismatch() {
        // Only two keys for a family of three live items — no safe pairing.
        let cpu = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "CPU 9%"),
            windowID: 10,
            bounds: CGRect(x: 0, y: 0, width: 40, height: 22)
        )
        let mem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "MEM 51%"),
            windowID: 11,
            bounds: CGRect(x: 50, y: 0, width: 40, height: 22)
        )
        let net = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "12.3 KB/s"),
            windowID: 12,
            bounds: CGRect(x: 100, y: 0, width: 40, height: 22)
        )
        let positions = [
            "status:com.bjango.istatmenus::com.bjango.istatmenus.cpu": 100,
            "status:com.bjango.istatmenus::com.bjango.istatmenus.memory": 200,
        ]

        XCTAssertNil(
            MenuBarAgentPositionStore.resolveKey(
                for: cpu,
                existingKeys: Array(positions.keys),
                positions: positions,
                liveItems: [cpu, mem, net]
            )
        )
    }

    func testResolvePositionalKeyNilWithoutSiblings() {
        // No siblings from the same app: title-based tiers already failed and
        // there's nothing to position-correlate against.
        let lone = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus", title: "CPU 9%"),
            windowID: 10,
            bounds: CGRect(x: 0, y: 0, width: 40, height: 22)
        )
        XCTAssertNil(
            MenuBarAgentPositionStore.resolveKey(
                for: lone,
                existingKeys: ["status:com.bjango.istatmenus::com.bjango.istatmenus.cpu"],
                positions: ["status:com.bjango.istatmenus::com.bjango.istatmenus.cpu": 100],
                liveItems: [lone]
            )
        )
    }

    // MARK: - neighborItems

    func testRightOfItemBracketsAnchorAndRightNeighbor() {
        let a = item("A", x: 0)
        let target = item("T", x: 30)
        let c = item("C", x: 60)
        let result = MenuBarAgentPositionStore.neighborItems(
            forMoving: a,
            to: .rightOfItem(target),
            liveItems: [a, target, c]
        )
        XCTAssertEqual(result?.anchor.tag.title, "T")
        XCTAssertEqual(result?.far?.tag.title, "C")
    }

    func testLeftOfItemFarNeighborNilAtRunStart() {
        // Anchor is leftmost after the moved item is removed → no far neighbor.
        let moved = item("M", x: 90)
        let target = item("T", x: 0)
        let c = item("C", x: 30)
        let result = MenuBarAgentPositionStore.neighborItems(
            forMoving: moved,
            to: .leftOfItem(target),
            liveItems: [target, c, moved]
        )
        XCTAssertEqual(result?.anchor.tag.title, "T")
        XCTAssertNil(result?.far)
    }

    // MARK: - move orchestration

    func testMoveWritesMidpointAndNudges() {
        let a = item("A", x: 0)
        let target = item("T", x: 30)
        let c = item("C", x: 60)

        var written: [String: Int]?
        var nudged = false
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: { ["status:A::A": 50, "status:A::T": 100, "status:A::C": 200] },
            writePositions: { written = $0 },
            nudgeAgent: { nudged = true }
        )

        let applied = MenuBarAgentPositionStore.move(
            item: a,
            to: .rightOfItem(target),
            liveItems: [a, target, c],
            environment: env
        )

        XCTAssertTrue(applied)
        XCTAssertTrue(nudged)
        // A is placed between T (100) and C (200).
        XCTAssertEqual(written?["status:A::A"], 150)
        // Other weights are untouched.
        XCTAssertEqual(written?["status:A::T"], 100)
        XCTAssertEqual(written?["status:A::C"], 200)
    }

    func testMoveDefersWhenKeyUnresolved() {
        let a = item("A", x: 0)
        let target = item("T", x: 30)
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: { ["status:A::T": 100] }, // no key for A
            writePositions: { _ in XCTFail("should not write") },
            nudgeAgent: { XCTFail("should not nudge") }
        )
        XCTAssertFalse(
            MenuBarAgentPositionStore.move(
                item: a,
                to: .rightOfItem(target),
                liveItems: [a, target],
                environment: env
            )
        )
    }

    func testMoveDefersWhenNoGap() {
        let a = item("A", x: 0)
        let target = item("T", x: 30)
        let c = item("C", x: 60)
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: { ["status:A::A": 50, "status:A::T": 100, "status:A::C": 101] },
            writePositions: { _ in XCTFail("should not write") },
            nudgeAgent: { XCTFail("should not nudge") }
        )
        XCTAssertFalse(
            MenuBarAgentPositionStore.move(
                item: a,
                to: .rightOfItem(target),
                liveItems: [a, target, c],
                environment: env
            )
        )
    }

    func testExperimentalMoveCanTargetAnchoredSystemItem() {
        let a = item("A", x: 0)
        let clock = MenuBarItem.fixture(
            tag: .clock,
            windowID: 90,
            bounds: CGRect(x: 30, y: 0, width: 24, height: 22)
        )
        let c = item("C", x: 60)

        var written: [String: Int]?
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: {
                [
                    "status:com.test.A::A": 50,
                    "module:Clock": 100,
                    "status:com.test.A::C": 200,
                ]
            },
            writePositions: { written = $0 },
            nudgeAgent: {}
        )

        XCTAssertFalse(
            MenuBarAgentPositionStore.move(
                item: a,
                to: .rightOfItem(clock),
                liveItems: [a, clock, c],
                environment: env
            )
        )

        XCTAssertTrue(
            MenuBarAgentPositionStore.move(
                item: a,
                to: .rightOfItem(clock),
                liveItems: [a, clock, c],
                experimentalSystemItemHiding: true,
                environment: env
            )
        )
        XCTAssertEqual(written?["status:com.test.A::A"], 150)
    }

    func testExperimentalMoveDoesNotTargetSystemUIServerItem() {
        let a = item("A", x: 0)
        let siri = MenuBarItem.fixture(
            tag: MenuBarItemTag(namespace: .systemUIServer, title: "Siri", windowID: 91),
            windowID: 91,
            bounds: CGRect(x: 30, y: 0, width: 24, height: 22)
        )
        let c = item("C", x: 60)
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: {
                [
                    "status:com.test.A::A": 50,
                    "status:com.apple.systemuiserver::Siri": 100,
                    "status:com.test.A::C": 200,
                ]
            },
            writePositions: { _ in XCTFail("should not write") },
            nudgeAgent: { XCTFail("should not nudge") }
        )

        XCTAssertFalse(
            MenuBarAgentPositionStore.move(
                item: a,
                to: .rightOfItem(siri),
                liveItems: [a, siri, c],
                experimentalSystemItemHiding: true,
                environment: env
            )
        )
    }

    // MARK: - applyOrder (batch)

    func testApplyOrderPermutesExistingWeightsIntoDesiredOrder() {
        // Live order A,B,C (x ascending) with ascending weight axis. Want C,A,B.
        let a = item("A", x: 0)
        let b = item("B", x: 30)
        let c = item("C", x: 60)
        var written: [String: Int]?
        var nudges = 0
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: { ["status:com.test.A::A": 100, "status:com.test.A::B": 200, "status:com.test.A::C": 300] },
            writePositions: { written = $0 },
            nudgeAgent: { nudges += 1 }
        )

        let changed = MenuBarAgentPositionStore.applyOrder(
            desiredOrder: [c.uniqueIdentifier, a.uniqueIdentifier, b.uniqueIdentifier],
            liveItems: [a, b, c],
            environment: env
        )

        // The segment's own slots {100,200,300} are reassigned in desired order:
        // C leftmost → 100, A → 200, B → 300. One write, one nudge.
        XCTAssertEqual(written?["status:com.test.A::C"], 100)
        XCTAssertEqual(written?["status:com.test.A::A"], 200)
        XCTAssertEqual(written?["status:com.test.A::B"], 300)
        XCTAssertEqual(nudges, 1)
        XCTAssertEqual(Set(changed), [a.uniqueIdentifier, b.uniqueIdentifier, c.uniqueIdentifier])
    }

    func testApplyOrderNoopWhenAlreadyOrdered() {
        let a = item("A", x: 0)
        let b = item("B", x: 30)
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: { ["status:com.test.A::A": 100, "status:com.test.A::B": 200] },
            writePositions: { _ in XCTFail("should not write") },
            nudgeAgent: { XCTFail("should not nudge") }
        )
        let changed = MenuBarAgentPositionStore.applyOrder(
            desiredOrder: [a.uniqueIdentifier, b.uniqueIdentifier],
            liveItems: [a, b],
            environment: env
        )
        XCTAssertTrue(changed.isEmpty)
    }

    func testApplyOrderHonorsDescendingAxis() {
        // Same desired order, but the live axis descends (leftmost has the
        // largest weight). Slots must be assigned high→low so C still lands left.
        let a = item("A", x: 0)
        let b = item("B", x: 30)
        let c = item("C", x: 60)
        var written: [String: Int]?
        let env = MenuBarAgentPositionStore.Environment(
            readPositions: { ["status:com.test.A::A": 300, "status:com.test.A::B": 200, "status:com.test.A::C": 100] },
            writePositions: { written = $0 },
            nudgeAgent: {}
        )
        _ = MenuBarAgentPositionStore.applyOrder(
            desiredOrder: [c.uniqueIdentifier, a.uniqueIdentifier, b.uniqueIdentifier],
            liveItems: [a, b, c],
            environment: env
        )
        // Descending axis: leftmost desired (C) gets the largest slot (300).
        XCTAssertEqual(written?["status:com.test.A::C"], 300)
        XCTAssertEqual(written?["status:com.test.A::A"], 200)
        XCTAssertEqual(written?["status:com.test.A::B"], 100)
    }

    // MARK: - Helpers

    /// A movable third-party status item under the "A" app at the given x.
    private func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.test.A", title: title),
            windowID: CGWindowID(abs(x.hashValue % 100_000) + 10),
            bounds: CGRect(x: x, y: 0, width: 24, height: 22)
        )
    }
}
