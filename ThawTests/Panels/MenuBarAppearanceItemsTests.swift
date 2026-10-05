//
//  MenuBarAppearanceItemsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
struct MenuBarAppearanceItemsTests {
    @Test("A partial on-screen snapshot cannot limit a reveal's owner read", arguments: [false, true])
    func revealReadsOwnersMissingFromOnScreenSnapshot(snapshotAfterReveal: Bool) async throws {
        let visible = [item(1, x: 300), item(2, x: 400)]
        let concealed = [item(3, x: -1, onScreen: false), item(4, x: -1, onScreen: false)]
        let physical = visible + [item(3, x: 100), item(4, x: 200)]
        let onScreen = OnScreenItemSnapshot()
        if !snapshotAfterReveal { onScreen.update(visible) }
        let revealAt = ContinuousClock.now
        if snapshotAfterReveal { onScreen.update(visible) }
        var requestedOwners = Set<pid_t>()
        let result = try #require(await MenuBarAppearanceItems.read(
            knownItems: visible + concealed,
            onScreenSnapshot: onScreen,
            notBefore: revealAt,
            readOwners: { owners in
                requestedOwners = owners
                return physical.filter { owners.contains($0.sourcePID ?? $0.ownerPID) }
            },
            discover: { Issue.record("A reveal must not wait for discovery"); return [] }
        ))

        #expect(requestedOwners == [1, 2, 3, 4])
        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: result.items,
            context: .init(revealedSection: .hidden, section: { ($0.sourcePID ?? 0) > 2 ? .hidden : .visible })
        )
        #expect(bounds.map(\.minX).min() == 100, "The first read must cover the newly revealed items")
    }

    @Test("An empty on-screen snapshot still reads known concealed owners")
    func knownInventoryDoesNotFallBackToDiscovery() async throws {
        let known = item(3, x: -1, onScreen: false)
        var requestedOwners = Set<pid_t>()
        let result = try #require(await MenuBarAppearanceItems.read(
            knownItems: [known], onScreenSnapshot: nil, notBefore: nil,
            readOwners: { owners in requestedOwners = owners; return [item(3, x: 100)] },
            discover: { Issue.record("Known owners do not require discovery"); return [] }
        ))
        #expect(requestedOwners == [3])
        #expect(result.items.count == 1)
    }

    @Test("A recent complete snapshot avoids another AX read")
    func completeSnapshotIsReused() async throws {
        let items = [item(1, x: 300), item(2, x: 400)]
        let revealAt = ContinuousClock.now
        let onScreen = OnScreenItemSnapshot()
        onScreen.update(items)
        let result = try #require(await MenuBarAppearanceItems.read(
            knownItems: items, onScreenSnapshot: onScreen, notBefore: revealAt,
            readOwners: { _ in Issue.record("The complete snapshot is already fresh"); return nil },
            discover: { Issue.record("Unexpected discovery"); return [] }
        ))
        #expect(result.items == items)
        #expect(result.readAt == onScreen.timestamp)
    }

    @Test("An incomplete requested-owner read preserves the previous geometry")
    func incompleteReadDoesNotPublishPartialGeometry() async {
        let known = item(3, x: -1, onScreen: false)
        let result = await MenuBarAppearanceItems.read(
            knownItems: [known], onScreenSnapshot: nil, notBefore: nil,
            readOwners: { _ in nil },
            discover: { Issue.record("Do not turn a failed read into discovery"); return [] }
        )
        #expect(result == nil)
    }

    @Test("The appearance pill follows mirrored status items on each display", arguments: [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: -2048, y: 0, width: 2048, height: 1152),
        CGRect(x: 1920, y: 0, width: 1280, height: 900),
        CGRect(x: 0, y: 1080, width: 1600, height: 900),
        CGRect(x: 0, y: -1200, width: 1600, height: 1200),
    ])
    func mirroredAppearanceGeometry(destination: CGRect) {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let source = item(1, x: 1583, namespace: .menuBarAgent)
        let snapshot = MenuBarAppearanceItems.Snapshot(items: [source], readAt: .now)
        let result = MenuBarAppearanceItems.geometry(
            from: snapshot, on: destination, displayBounds: [primary, destination],
            context: .init(revealedSection: nil, section: { _ in .visible })
        )
        let expected = CGRect(x: destination.maxX - 337, y: destination.minY + 3, width: 24, height: 24)
        #expect(result.itemBounds == [expected])
        #expect(result.readAt == snapshot.readAt)

        let pill = MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: result.itemBounds,
            in: CGRect(x: 0, y: 0, width: destination.width, height: 30),
            screenFrame: destination, leadingOutset: 6, trailingOutset: 6,
            notchFrame: nil, notchMargin: 0
        )
        #expect(pill.width == 36)
        #expect(pill.minX == destination.width - 343)
    }

    @Test("Mirroring preserves section and parked-item exclusions", arguments: [false, true])
    func mirroredGeometryKeepsExclusions(revealed: Bool) {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: -2048, y: 0, width: 2048, height: 1152)
        let items = [
            item(1, x: 1583, namespace: .menuBarAgent),
            item(2, x: 1500),
            item(3, x: -1),
            item(4, x: 1000, y: 1000),
            item(5, x: 1100, title: "System Status Item Clone"),
            item(6, x: 1200, onScreen: false),
            item(7, x: 1300, namespace: .thaw, title: "Thaw.ControlItem.Hidden"),
            item(8, x: 1400),
        ]
        let result = MenuBarAppearanceItems.geometry(
            from: .init(items: items, readAt: .now), on: secondary,
            displayBounds: [primary, secondary],
            context: .init(revealedSection: revealed ? .hidden : nil, section: {
                switch $0.sourcePID {
                case 2: .hidden
                case 8: .alwaysHidden
                default: .visible
                }
            })
        )
        #expect(result.itemBounds.map(\.minX).sorted() == (revealed ? [-420, -337] : [-337]))
    }

    @Test("The mirrored chevron and trailing stand-in use the destination display", arguments: [false, true], [
        CGRect(x: -2048, y: 0, width: 2048, height: 1152),
        CGRect(x: 1920, y: 0, width: 1280, height: 900),
        CGRect(x: 0, y: 1080, width: 1600, height: 900),
        CGRect(x: 0, y: -1200, width: 1600, height: 1200),
    ])
    func mirroredChevronAndStandIn(revealed: Bool, secondary: CGRect) {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let chevron = item(1, x: 1720, namespace: .thaw, title: "Thaw.ControlItem.Visible")
        let result = MenuBarAppearanceItems.geometry(
            from: .init(items: [chevron], readAt: .now), on: secondary,
            displayBounds: [primary, secondary],
            context: .init(revealedSection: revealed ? .hidden : nil, section: { _ in .visible })
        )
        let expectedChevron = CGRect(x: secondary.maxX - 200, y: secondary.minY + 3, width: 24, height: 24)
        #expect(result.chevronFrame == (revealed ? .zero : expectedChevron))
        #expect(result.itemBounds.map(\.maxX).max() == secondary.maxX)
        #expect(result.itemBounds.map(\.minX).min() == expectedChevron.minX)
        #expect(result.itemBounds.allSatisfy { $0.minY == secondary.minY + 3 })
    }

    @Test("A mirrored pill follows Sound's post-startup leftward movement", arguments: [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: -2048, y: 0, width: 2048, height: 1152),
        CGRect(x: 0, y: 1080, width: 1600, height: 900),
    ])
    func mirroredPillFollowsSound(destination: CGRect) {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let snapshot = MenuBarAppearanceItems.geometry(
            from: .init(items: [
                item(1, x: 1614, namespace: .menuBarAgent, title: "com.apple.menuextra.sound"),
                item(2, x: 1835, namespace: .menuBarAgent, title: "com.apple.menuextra.clock"),
            ], readAt: .now),
            on: destination, displayBounds: [primary, destination],
            context: .init(revealedSection: nil, section: { _ in .visible })
        )
        #expect(snapshot.sourceScreenFrame == primary)
        let stable = MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: snapshot.itemBounds,
            in: CGRect(x: 0, y: 5, width: destination.width, height: 30),
            screenFrame: destination, leadingOutset: 7, trailingOutset: 7,
            notchFrame: nil, notchMargin: 0
        )
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            .init(x: 1583, screenFrame: primary), itemBounds: snapshot.itemBounds,
            stableTrailingBounds: stable, screenFrame: destination, revealedSection: nil,
            sourceScreenFrame: snapshot.sourceScreenFrame
        )
        #expect(updated.itemBounds.map(\.minX).min() == destination.maxX - 337)
        #expect(updated.stableTrailingBounds.minX == stable.minX - 31)
        #expect(updated.stableTrailingBounds.maxX == stable.maxX)
    }

    @Test("Mixed source displays cannot authorize another display's edge correction")
    func mixedSourcesHaveNoSharedEdge() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let secondary = CGRect(x: -2048, y: 0, width: 2048, height: 1152)
        let snapshot = MenuBarAppearanceItems.geometry(
            from: .init(items: [item(1, x: 1614), item(2, x: -200)], readAt: .now),
            on: secondary, displayBounds: [primary, secondary],
            context: .init(revealedSection: nil, section: { _ in .visible })
        )
        #expect(snapshot.sourceScreenFrame == nil)
    }

    private func item(
        _ sourcePID: pid_t,
        x: CGFloat,
        y: CGFloat = 3,
        onScreen: Bool = true,
        namespace: MenuBarItemTag.Namespace? = nil,
        title: String = "Status"
    ) -> MenuBarItem {
        MenuBarItem(
            tag: .init(namespace: namespace ?? .string("com.example.owner\(sourcePID)"), title: title, instanceIndex: 0),
            windowID: UInt32(sourcePID), ownerPID: 99, sourcePID: sourcePID,
            bounds: CGRect(x: x, y: y, width: 24, height: 24), title: title, isOnScreen: onScreen
        )
    }
}
