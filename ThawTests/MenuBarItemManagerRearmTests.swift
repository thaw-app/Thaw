//
//  MenuBarItemManagerRearmTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Verifies the cache-refresh contract of rearmActiveProfileLayout, the half
/// of the fix that lives in MenuBarItemManager.
///
/// The late-arrival re-sort reads activeProfileLayout (its sectionOrder /
/// itemSectionMap) and activeProfileItemIdentifiers. When the user updates the
/// active profile, re-arming must refresh both so the next re-sort targets the
/// updated layout instead of the spec frozen at the last apply. This is exactly
/// the reversion that dragged items back into Always-Hidden in the field logs.
@MainActor
final class MenuBarItemManagerRearmTests: XCTestCase {
    /// Re-arming on a fresh manager refreshes both the cached layout and the
    /// flattened identifier set the late-arrival detector consults.
    func testRearmRefreshesCachedLayoutAndIdentifiers() {
        let manager = MenuBarItemManager()
        XCTAssertNil(manager.activeProfileLayout, "Nothing should be armed before a profile is applied or updated")

        let sectionOrder = [
            "hidden": ["com.example.a:Item-0", "com.example.b:Item-0"],
            "alwaysHidden": [String](),
        ]
        let itemSectionMap = [
            "com.example.a:Item-0": "hidden",
            "com.example.b:Item-0": "hidden",
        ]

        manager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: sectionOrder,
            itemSectionMap: itemSectionMap,
            itemOrder: sectionOrder
        )

        XCTAssertEqual(manager.activeProfileLayout?.sectionOrder, sectionOrder)
        XCTAssertEqual(manager.activeProfileLayout?.itemSectionMap, itemSectionMap)
        XCTAssertEqual(
            manager.activeProfileItemIdentifiers,
            ["com.example.a:Item-0", "com.example.b:Item-0"]
        )
    }

    /// Reproduces the field reversion at the cache level: a profile is applied
    /// with an item in Always-Hidden, the user moves it to Hidden and updates
    /// the profile, and re-arming must move the cached section to Hidden. With
    /// the pre-fix no-op, the cache would stay on the Always-Hidden spec and the
    /// next late-arrival re-sort would drag the item back into Always-Hidden.
    func testRearmMovesCachedItemFromAlwaysHiddenToHidden() {
        let manager = MenuBarItemManager()
        let uid = "com.if.Amphetamine:Amphetamine"

        // State A: as applied — item lives in Always-Hidden.
        manager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["alwaysHidden": [uid]],
            itemSectionMap: [uid: "alwaysHidden"],
            itemOrder: ["alwaysHidden": [uid]]
        )
        XCTAssertEqual(
            manager.activeProfileLayout?.itemSectionMap[uid],
            "alwaysHidden",
            "Precondition: the applied spec has the item in Always-Hidden"
        )

        // State B: user moved it to Hidden and updated the active profile.
        manager.rearmActiveProfileLayout(
            pinnedHidden: [],
            pinnedAlwaysHidden: [],
            sectionOrder: ["hidden": [uid]],
            itemSectionMap: [uid: "hidden"],
            itemOrder: ["hidden": [uid]]
        )

        XCTAssertEqual(
            manager.activeProfileLayout?.itemSectionMap[uid],
            "hidden",
            "Re-arm must refresh the cached section so the late-arrival re-sort targets the updated layout, not the pre-update spec"
        )
        XCTAssertEqual(manager.activeProfileItemIdentifiers, [uid])
    }

    func testMacOS27RetainsLastGoodCacheWhenVisibleControlItemDisappears() {
        let previous = [
            MenuBarItem.fixture(
                tag: .visibleControlItem,
                windowID: 1,
                bounds: CGRect(x: 2368, y: 3, width: 35, height: 24)
            ),
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.status", title: "Status"),
                windowID: 2
            ),
        ]
        let snapshot = [
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.status", title: "Status"),
                windowID: 2
            ),
        ]

        XCTAssertTrue(
            MenuBarItemManager.shouldRetainLastGoodCacheForMissingVisibleControlItem(
                snapshotItems: snapshot,
                previousCachedItems: previous,
                supportsLegacySectionHiding: false
            )
        )
    }

    func testMacOS27SynthesizesDividerControlsOnlyWhenVisibleControlItemPresent() {
        let snapshotWithVisibleControl = [
            MenuBarItem.fixture(
                tag: .visibleControlItem,
                windowID: 1,
                bounds: CGRect(x: 2368, y: 3, width: 35, height: 24)
            ),
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.status", title: "Status"),
                windowID: 2
            ),
        ]
        let snapshotWithoutVisibleControl = [
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.status", title: "Status"),
                windowID: 2
            ),
        ]

        XCTAssertTrue(
            MenuBarItemManager.canSynthesizeMacOS27ControlItems(
                snapshotItems: snapshotWithVisibleControl,
                supportsLegacySectionHiding: false
            )
        )
        XCTAssertFalse(
            MenuBarItemManager.canSynthesizeMacOS27ControlItems(
                snapshotItems: snapshotWithoutVisibleControl,
                supportsLegacySectionHiding: false
            )
        )
    }

    func testMoveInputSuppressionSuppressesUntaggedMouseMovement() throws {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))

        XCTAssertTrue(MoveInputSuppression.shouldSuppress(event))
    }

    func testMoveInputSuppressionAllowsTaggedSyntheticMovement() throws {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))

        MoveInputSuppression.markSyntheticMoveEvent(event)

        XCTAssertFalse(MoveInputSuppression.shouldSuppress(event))
    }

    func testMoveInputSuppressionAllowsLegacyMenuBarEvents() throws {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))

        event.setIntegerValueField(.eventSourceUserData, value: 1)

        XCTAssertFalse(MoveInputSuppression.shouldSuppress(event))
    }

    func testMoveInputSuppressionIgnoresKeyboardEvents() throws {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ))

        XCTAssertFalse(MoveInputSuppression.shouldSuppress(event))
    }
}
