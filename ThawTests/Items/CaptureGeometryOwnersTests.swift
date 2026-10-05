//
//  CaptureGeometryOwnersTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Thumbnail geometry owners")
struct CaptureGeometryOwnersTests {
    @Test("A capture refreshes its own items, every known item and recent neighbours")
    func ownersCoverTargetsKnownItemsAndNeighbours() {
        let owners = MenuBarItemImageCache.captureGeometryOwners(
            for: [item(1)],
            knownItems: [item(1), item(2), item(3)],
            recentItems: [item(2), item(4)]
        )
        #expect(owners == [1, 2, 3, 4])
    }

    @Test("An item hosted by another process is read through its source")
    func hostedItemUsesItsSource() {
        let owners = MenuBarItemImageCache.captureGeometryOwners(
            for: [item(7, ownerPID: 99)],
            knownItems: [item(nil, ownerPID: 42)],
            recentItems: []
        )
        #expect(owners == [7, 42])
    }

    @Test("Nothing to capture asks for no owners")
    func noTargetsNoOwners() {
        let owners = MenuBarItemImageCache.captureGeometryOwners(
            for: [],
            knownItems: [item(2)],
            recentItems: [item(3)]
        )
        #expect(owners.isEmpty)
    }

    @Test("Known owners are read without walking every app")
    func knownOwnersSkipDiscovery() async {
        var requested = Set<pid_t>()
        let items = await MenuBarItemImageCache.freshCaptureGeometry(
            owners: [1, 2],
            readOwners: { owners in
                requested = owners
                return [item(1), item(2)]
            },
            discover: {
                Issue.record("A complete known-owner read must not fall back to discovery")
                return []
            }
        )
        #expect(requested == [1, 2])
        #expect(items.map(\.sourcePID) == [1, 2])
    }

    @Test("A read that missed a neighbour falls back to the walk of every app")
    func missedNeighbourFallsBackToDiscovery() async {
        var discoveries = 0
        let items = await MenuBarItemImageCache.freshCaptureGeometry(
            owners: [1],
            readOwners: { _ in nil },
            discover: {
                discoveries += 1
                return [item(1), item(5)]
            }
        )
        #expect(discoveries == 1)
        #expect(items.map(\.sourcePID) == [1, 5])
    }

    @Test("A complete read that found nothing is not mistaken for a failed one")
    func emptyReadIsAnAnswer() async {
        let items = await MenuBarItemImageCache.freshCaptureGeometry(
            owners: [1],
            readOwners: { _ in [] },
            discover: {
                Issue.record("An empty answer is still an answer")
                return [item(1)]
            }
        )
        #expect(items.isEmpty)
    }

    @Test("A reader given no owners keeps the walk of every app")
    func noOwnersDiscover() async {
        var discoveries = 0
        _ = await MenuBarItemImageCache.freshCaptureGeometry(
            owners: [],
            readOwners: { _ in
                Issue.record("There is no owner to read")
                return nil
            },
            discover: {
                discoveries += 1
                return []
            }
        )
        #expect(discoveries == 1)
    }

    private func item(_ sourcePID: pid_t?, ownerPID: pid_t = 99) -> MenuBarItem {
        MenuBarItem(
            tag: .init(
                namespace: .string("com.example.owner\(sourcePID ?? ownerPID)"),
                title: "Status",
                instanceIndex: 0
            ),
            windowID: UInt32(sourcePID ?? ownerPID),
            ownerPID: ownerPID,
            sourcePID: sourcePID,
            bounds: CGRect(x: 100, y: 3, width: 24, height: 24),
            title: "Status",
            isOnScreen: true
        )
    }
}
