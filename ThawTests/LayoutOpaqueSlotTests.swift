//
//  LayoutOpaqueSlotTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class LayoutOpaqueSlotTests: XCTestCase {
    func testDescriptorRequiresRunningAgentAndRuntimePosition() {
        let running = Set([LayoutOpaqueSlotDescriptor.littleSnitchBundleIdentifier])
        let positions = [LayoutOpaqueSlotDescriptor.littleSnitchRuntimePositionKey: 200]

        XCTAssertNotNil(LayoutOpaqueSlotDescriptor.littleSnitch(runningBundleIdentifiers: running, positions: positions))
        XCTAssertNil(LayoutOpaqueSlotDescriptor.littleSnitch(runningBundleIdentifiers: [], positions: positions))
        XCTAssertNil(LayoutOpaqueSlotDescriptor.littleSnitch(runningBundleIdentifiers: running, positions: [:]))
    }

    func testDescriptorReplacesResolvedAndUnresolvedTilesWithOneSlot() throws {
        try XCTSkipUnless(isRunningOnMacOS27OrLater)
        let descriptor = try XCTUnwrap(makeDescriptor())
        let resolved = makeItem(tag: .appItem(bundleID: descriptor.bundleIdentifier, title: "Item-0"))
        let unresolved = makeItem(tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0"))
        let neighbor = makeItem(tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor"))

        let displayed = [resolved, neighbor, unresolved].filter { !descriptor.matchesOpaqueItem($0) }

        XCTAssertEqual(displayed.map(\.tag), [neighbor.tag])
    }

    func testRuntimeKeyRemovalRemovesOpaqueAndStaleStandardTiles() throws {
        try XCTSkipUnless(isRunningOnMacOS27OrLater)
        let resolved = makeItem(
            tag: .appItem(bundleID: LayoutOpaqueSlotDescriptor.littleSnitchBundleIdentifier, title: "Item-0")
        )
        let unresolved = makeItem(tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0"))
        let neighbor = makeItem(tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor"))

        let descriptor = LayoutOpaqueSlotDescriptor.littleSnitch(
            runningBundleIdentifiers: [LayoutOpaqueSlotDescriptor.littleSnitchBundleIdentifier],
            positions: [:]
        )
        let displayed = LayoutOpaqueSlotDescriptor.itemsForLayout(
            [resolved, unresolved, neighbor],
            suppressUnresolvedSlot: true
        )

        XCTAssertNil(descriptor)
        XCTAssertEqual(displayed.map(\.tag), [neighbor.tag])
    }

    func testStoppedAgentKeepsStaleUnresolvedTileSuppressedAcrossRebuilds() throws {
        try XCTSkipUnless(isRunningOnMacOS27OrLater)
        let unresolved = makeItem(tag: MenuBarItemTag(namespace: .menuBarAgent, title: "Item-0"))
        let neighbor = makeItem(tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor"))
        let items = [unresolved, neighbor]

        let firstSuppression = LayoutOpaqueSlotDescriptor.shouldSuppressUnresolvedSlot(
            in: items,
            littleSnitchRunning: false,
            wasSuppressed: true
        )
        let secondSuppression = LayoutOpaqueSlotDescriptor.shouldSuppressUnresolvedSlot(
            in: items,
            littleSnitchRunning: false,
            wasSuppressed: firstSuppression
        )

        let displayed = LayoutOpaqueSlotDescriptor.itemsForLayout(
            items,
            suppressUnresolvedSlot: secondSuppression
        )

        XCTAssertTrue(firstSuppression)
        XCTAssertTrue(secondSuppression)
        XCTAssertEqual(displayed.map(\.tag), [neighbor.tag])
    }

    func testStoppedAgentClearsSuppressionAfterUnresolvedTileLeavesCache() {
        let neighbor = makeItem(tag: .appItem(bundleID: "com.example.neighbor", title: "Neighbor"))

        XCTAssertFalse(
            LayoutOpaqueSlotDescriptor.shouldSuppressUnresolvedSlot(
                in: [neighbor],
                littleSnitchRunning: false,
                wasSuppressed: true
            )
        )
    }

    func testInsertionOrderUsesRuntimeWeightBetweenModeledNeighbors() {
        let references = [
            (index: 0, x: CGFloat(100), weight: 100),
            (index: 1, x: CGFloat(200), weight: 300),
        ]

        XCTAssertEqual(
            LayoutOpaqueSlotDescriptor.insertionIndex(
                opaqueWeight: 200,
                references: references,
                fallback: 2
            ),
            1
        )
    }

    func testInsertionOrderHandlesDescendingRuntimeWeights() {
        let references = [
            (index: 0, x: CGFloat(100), weight: 300),
            (index: 1, x: CGFloat(200), weight: 100),
        ]

        XCTAssertEqual(
            LayoutOpaqueSlotDescriptor.insertionIndex(
                opaqueWeight: 200,
                references: references,
                fallback: 2
            ),
            1
        )
    }

    /// Replaces the `XCTUnwrap` calls in the anchored-insertion tests with
    /// a fail-on-nil guard. `XCTUnwrap` requires `throws`, but the test body
    /// is synchronous and we want a clear failure message instead.
    private func requireAnchoredIndex(
        _ result: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Int {
        guard let result else {
            XCTFail("Expected an anchored insertion index for a finite, positive anchor", file: file, line: line)
            return .max
        }
        return result
    }

    /// Reproduces the off-by-2-3-items regression where the LS app-icon slot
    /// landed at the wrong menu-bar position because the weight heuristic
    /// compared the LS preferred-position weight against the saved weights
    /// of its neighbours, and those weights lagged behind the live bar after
    /// recent reorder / title churn.
    ///
    /// The fix anchors the slot on the LS item's live AX `midX` against the
    /// displayed neighbours' `midX` (also live), so the saved weights no
    /// longer participate. `displayedItems` already excludes the LS item;
    /// given three neighbours at midX 100/220/360 and an LS anchor at 230,
    /// the slot must insert at index 1 (just before the 220 neighbour —
    /// `midX >= anchorX`).
    func testInsertionByAnchorXPlacesSlotAtLivePosition() {
        let displayedItems = [
            makeItemAtX(tag: .appItem(bundleID: "com.example.alpha", title: "A"), x: 100),
            makeItemAtX(tag: .appItem(bundleID: "com.example.bravo", title: "B"), x: 220),
            makeItemAtX(tag: .appItem(bundleID: "com.example.charlie", title: "C"), x: 360),
        ]
        let result = requireAnchoredIndex(
            LayoutOpaqueSlotDescriptor.insertionIndex(
                byAnchorX: CGFloat(230),
                in: displayedItems
            )
        )
        // Index 1 — slot sits between the alpha (midX=100) and bravo
        // (midX=220) neighbours, matching where Little Snitch actually is.
        XCTAssertEqual(result, 1)
    }

    /// An anchor to the right of every neighbour clamps to `endIndex` so the
    /// slot trails the last item rather than being dropped or moved into the
    /// bar.
    func testInsertionByAnchorXRightOfAllNeighboursClampsToEnd() {
        let displayedItems = [
            makeItemAtX(tag: .appItem(bundleID: "com.example.alpha", title: "A"), x: 100),
            makeItemAtX(tag: .appItem(bundleID: "com.example.bravo", title: "B"), x: 220),
        ]
        let result = requireAnchoredIndex(
            LayoutOpaqueSlotDescriptor.insertionIndex(
                byAnchorX: CGFloat(500),
                in: displayedItems
            )
        )
        XCTAssertEqual(result, displayedItems.endIndex)
    }

    /// A non-finite or non-positive anchor must return `nil` so the caller
    /// can fall back to the weight heuristic instead of inserting at a
    /// meaningless index.
    func testInsertionByAnchorXRejectsUnusableAnchor() {
        XCTAssertNil(
            LayoutOpaqueSlotDescriptor.insertionIndex(byAnchorX: .nan, in: [])
        )
        XCTAssertNil(
            LayoutOpaqueSlotDescriptor.insertionIndex(byAnchorX: 0, in: [])
        )
        XCTAssertNil(
            LayoutOpaqueSlotDescriptor.insertionIndex(byAnchorX: -1, in: [])
        )
    }

    @MainActor
    func testOpaqueViewIsInformationalAndNonDraggable() throws {
        let descriptor = try XCTUnwrap(makeDescriptor())
        let view = LayoutOpaqueSlotView(descriptor: descriptor, runningApplications: [])

        XCTAssertFalse(view.isEnabled)
        XCTAssertEqual(view.accessibilityLabel(), descriptor.accessibilityLabel)
        XCTAssertEqual(view.accessibilityHelp(), descriptor.tooltip)
        XCTAssertEqual(descriptor.badgeSystemImage, "eye.slash")
        XCTAssertEqual(descriptor.badgeReason, "Reliable menu bar preview unavailable")
        guard case let .opaqueSlot(renderedDescriptor) = view.kind else {
            return XCTFail("Expected an opaque informational slot")
        }
        XCTAssertEqual(renderedDescriptor, descriptor)
    }

    @MainActor
    func testAppIconSelectionUsesRequestedBundleIdentifier() {
        let expected = NSImage(size: CGSize(width: 16, height: 16))
        let applications = [
            FakeApplication(bundleIdentifier: "com.example.other", icon: NSImage(size: CGSize(width: 16, height: 16))),
            FakeApplication(bundleIdentifier: LayoutOpaqueSlotDescriptor.littleSnitchBundleIdentifier, icon: expected),
        ]

        let selected = LayoutOpaqueSlotDescriptor.appIcon(
            bundleIdentifier: LayoutOpaqueSlotDescriptor.littleSnitchBundleIdentifier,
            applications: applications
        )

        XCTAssertIdentical(selected, expected)
    }

    private func makeDescriptor() -> LayoutOpaqueSlotDescriptor? {
        LayoutOpaqueSlotDescriptor.littleSnitch(
            runningBundleIdentifiers: [LayoutOpaqueSlotDescriptor.littleSnitchBundleIdentifier],
            positions: [LayoutOpaqueSlotDescriptor.littleSnitchRuntimePositionKey: 200]
        )
    }

    private func makeItem(tag: MenuBarItemTag) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 42,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22),
            title: tag.title,
            isOnScreen: true
        )
    }

    /// Neighbour fixture anchored at a specific on-screen X, used by the
    /// `insertionIndex(byAnchorX:in:)` regressions. The opaque slot insertion
    /// by anchor only reads `bounds.midX`, so the fixture zeroes everything
    /// else.
    private func makeItemAtX(tag: MenuBarItemTag, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: 42,
            ownerPID: 100,
            sourcePID: 100,
            bounds: CGRect(x: x, y: 0, width: 24, height: 22),
            title: tag.title,
            isOnScreen: true
        )
    }

    private struct FakeApplication: LayoutOpaqueSlotApplication {
        let bundleIdentifier: String?
        let icon: NSImage?
    }
}
