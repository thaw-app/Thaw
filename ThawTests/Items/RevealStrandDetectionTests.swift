//
//  RevealStrandDetectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Pins the verdict the reveal path uses to decide whether the batch
/// preferred-position write actually landed.
///
/// MenuBarAgent re-allows a concealed item at the slot it remembers, not the
/// weight on file, so after a reveal the bar, not the store, says whether a
/// member sits in its section. A hidden member standing right of the divider,
/// or a visible member standing left of it, is stranded and needs a physical
/// move; everything else is left alone.
@MainActor
@Suite("Reveal strand detection")
struct RevealStrandDetectionTests {
    private static func app(
        _ bundleID: String,
        _ title: String,
        x: CGFloat,
        windowID: UInt32
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

    private static func control(_ tag: MenuBarItemTag, title: String, x: CGFloat, windowID: UInt32) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: windowID,
            ownerPID: 501,
            sourcePID: 501,
            bounds: CGRect(x: x, y: 0, width: tag == .visibleControlItem ? 24 : 1, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static let hiddenDivider = control(
        .hiddenControlItem, title: ControlItemIdentifier.hidden.rawValue, x: 300, windowID: 1
    )
    private static let visibleControl = control(
        .visibleControlItem, title: ControlItemIdentifier.visible.rawValue, x: 600, windowID: 2
    )
    private static let controlItems = ControlItemPair(hidden: hiddenDivider, alwaysHidden: nil)

    @Test
    func hiddenMemberRevealedAmongVisibleOnesIsStranded() {
        // The reported bar: Shottr assigned Hidden, re-allowed by the agent
        // between two visible members instead of left of the divider.
        let dockDoor = Self.app("com.ethanbills.DockDoor", "Item-0", x: 350, windowID: 10)
        let shottr = Self.app("cc.ffitch.shottr", "Item-0", x: 400, windowID: 11)
        let raycast = Self.app("com.raycast.macos", "Item-0", x: 450, windowID: 12)
        let items = [Self.hiddenDivider, dockDoor, shottr, raycast, Self.visibleControl]

        let stranded = MenuBarItemManager.membersStrandedAcrossDivider(
            items: items,
            controlItems: Self.controlItems,
            sectionFor: { $0.tag == shottr.tag ? .hidden : .visible },
            experimentalSystemItemHiding: false
        )

        #expect(stranded.map(\.uniqueIdentifier) == [shottr.uniqueIdentifier])
    }

    @Test
    func anItemTheRepairLadderGaveUpOnIsNotStranded() {
        // Guards against the reveal path physically repairing an item the
        // ladder already suppressed as persistently stranded, which re-seats
        // its neighbours on every toggle. Uses ordinary third-party items so
        // the predicate is tested apart from the planner's system-item policy.
        let dockDoor = Self.app("com.ethanbills.DockDoor", "Item-0", x: 350, windowID: 30)
        let shottr = Self.app("cc.ffitch.shottr", "Item-0", x: 400, windowID: 31)
        let raycast = Self.app("com.raycast.macos", "Item-0", x: 450, windowID: 32)
        let items = [Self.hiddenDivider, dockDoor, shottr, raycast, Self.visibleControl]
        let sectionFor: (MenuBarItem) -> MenuBarSection.Name = {
            $0.tag == dockDoor.tag || $0.tag == shottr.tag ? .hidden : .visible
        }

        // Two hidden members standing right of the divider: both stranded.
        let unfiltered = MenuBarItemManager.membersStrandedAcrossDivider(
            items: items,
            controlItems: Self.controlItems,
            sectionFor: sectionFor,
            experimentalSystemItemHiding: false
        )
        #expect(unfiltered.map(\.uniqueIdentifier)
            == [dockDoor.uniqueIdentifier, shottr.uniqueIdentifier])

        // Suppressing one leaves the other to be repaired.
        let filtered = MenuBarItemManager.membersStrandedAcrossDivider(
            items: items,
            controlItems: Self.controlItems,
            sectionFor: sectionFor,
            experimentalSystemItemHiding: false,
            isRepairSuppressed: { $0.uniqueIdentifier == dockDoor.uniqueIdentifier }
        )
        #expect(filtered.map(\.uniqueIdentifier) == [shottr.uniqueIdentifier])
    }

    @Test
    func visibleMemberLeftStandingInHiddenBandIsStranded() {
        // The mirror case: an item moved to Visible while concealed keeps its
        // hidden-side slot on reveal.
        let proton = Self.app("ch.protonmail.drive", "Proton Drive", x: 200, windowID: 20)
        let shottr = Self.app("cc.ffitch.shottr", "Item-0", x: 250, windowID: 21)
        let weather = Self.app("com.apple.weather.menu", "Weather", x: 400, windowID: 22)
        let items = [proton, shottr, Self.hiddenDivider, weather, Self.visibleControl]

        let stranded = MenuBarItemManager.membersStrandedAcrossDivider(
            items: items,
            controlItems: Self.controlItems,
            sectionFor: { $0.tag == shottr.tag ? .hidden : .visible },
            experimentalSystemItemHiding: false
        )

        #expect(stranded.map(\.uniqueIdentifier) == [proton.uniqueIdentifier])
    }

    @Test
    func partitionedBarReportsNothing() {
        let shottr = Self.app("cc.ffitch.shottr", "Item-0", x: 250, windowID: 30)
        let dockDoor = Self.app("com.ethanbills.DockDoor", "Item-0", x: 350, windowID: 31)
        let raycast = Self.app("com.raycast.macos", "Item-0", x: 450, windowID: 32)
        let items = [shottr, Self.hiddenDivider, dockDoor, raycast, Self.visibleControl]

        let stranded = MenuBarItemManager.membersStrandedAcrossDivider(
            items: items,
            controlItems: Self.controlItems,
            sectionFor: { $0.tag == shottr.tag ? .hidden : .visible },
            experimentalSystemItemHiding: false
        )

        #expect(stranded.isEmpty)
    }

    @Test
    func controlItemsNeverCount() {
        // Thaw's own dividers are not members of any section; only ordinary
        // items can be stranded.
        let items = [Self.visibleControl, Self.hiddenDivider]

        let stranded = MenuBarItemManager.membersStrandedAcrossDivider(
            items: items,
            controlItems: Self.controlItems,
            sectionFor: { _ in .visible },
            experimentalSystemItemHiding: false
        )

        #expect(stranded.isEmpty)
    }
}
