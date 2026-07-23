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

    private struct FakeApplication: LayoutOpaqueSlotApplication {
        let bundleIdentifier: String?
        let icon: NSImage?
    }
}
