//
//  MenuBarShapesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

// MARK: - MenuBarEndCap Tests

final class MenuBarEndCapTests: XCTestCase {
    func testRawValues() {
        XCTAssertEqual(MenuBarEndCap.square.rawValue, 0)
        XCTAssertEqual(MenuBarEndCap.round.rawValue, 1)
    }

    func testInitFromRawValue() {
        XCTAssertEqual(MenuBarEndCap(rawValue: 0), .square)
        XCTAssertEqual(MenuBarEndCap(rawValue: 1), .round)
        XCTAssertNil(MenuBarEndCap(rawValue: 2))
    }

    func testAllCasesCount() {
        XCTAssertEqual(MenuBarEndCap.allCases.count, 2)
    }

    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for endCap in MenuBarEndCap.allCases {
            let data = try encoder.encode(endCap)
            let decoded = try decoder.decode(MenuBarEndCap.self, from: data)
            XCTAssertEqual(decoded, endCap)
        }
    }
}

// MARK: - MenuBarShapeKind Tests

final class MenuBarShapeKindTests: XCTestCase {
    func testRawValues() {
        XCTAssertEqual(MenuBarShapeKind.noShape.rawValue, 0)
        XCTAssertEqual(MenuBarShapeKind.full.rawValue, 1)
        XCTAssertEqual(MenuBarShapeKind.split.rawValue, 2)
        XCTAssertEqual(MenuBarShapeKind.notch.rawValue, 3)
    }

    func testInitFromRawValue() {
        XCTAssertEqual(MenuBarShapeKind(rawValue: 0), .noShape)
        XCTAssertEqual(MenuBarShapeKind(rawValue: 1), .full)
        XCTAssertEqual(MenuBarShapeKind(rawValue: 2), .split)
        XCTAssertEqual(MenuBarShapeKind(rawValue: 3), .notch)
        XCTAssertNil(MenuBarShapeKind(rawValue: 4))
    }

    func testAllCasesCount() {
        XCTAssertEqual(MenuBarShapeKind.allCases.count, 4)
    }

    func testIdentifiableId() {
        for kind in MenuBarShapeKind.allCases {
            XCTAssertEqual(kind.id, kind.rawValue)
        }
    }

    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for kind in MenuBarShapeKind.allCases {
            let data = try encoder.encode(kind)
            let decoded = try decoder.decode(MenuBarShapeKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }
}

// MARK: - MenuBarFullShapeInfo Tests

final class MenuBarFullShapeInfoTests: XCTestCase {
    func testDefaultValue() {
        let defaultInfo = MenuBarFullShapeInfo.defaultValue
        XCTAssertEqual(defaultInfo.leadingEndCap, .round)
        XCTAssertEqual(defaultInfo.trailingEndCap, .round)
    }

    func testHasRoundedShapeBothRound() {
        let info = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
        XCTAssertTrue(info.hasRoundedShape)
    }

    func testHasRoundedShapeLeadingRound() {
        let info = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square)
        XCTAssertTrue(info.hasRoundedShape)
    }

    func testHasRoundedShapeTrailingRound() {
        let info = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
        XCTAssertTrue(info.hasRoundedShape)
    }

    func testHasRoundedShapeBothSquare() {
        let info = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        XCTAssertFalse(info.hasRoundedShape)
    }

    func testCodable() throws {
        let original = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarFullShapeInfo.self, from: data)

        XCTAssertEqual(decoded.leadingEndCap, original.leadingEndCap)
        XCTAssertEqual(decoded.trailingEndCap, original.trailingEndCap)
    }

    func testHashable() {
        let info1 = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
        let info2 = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
        let info3 = MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)

        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
    }
}

// MARK: - MenuBarSplitShapeInfo Tests

final class MenuBarSplitShapeInfoTests: XCTestCase {
    func testDefaultValue() {
        let defaultInfo = MenuBarSplitShapeInfo.defaultValue
        XCTAssertEqual(defaultInfo.leading, MenuBarFullShapeInfo.defaultValue)
        XCTAssertEqual(defaultInfo.trailing, MenuBarFullShapeInfo.defaultValue)
    }

    func testHasRoundedShapeLeadingRounded() {
        let info = MenuBarSplitShapeInfo(
            leading: MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square),
            trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        )
        XCTAssertTrue(info.hasRoundedShape)
    }

    func testHasRoundedShapeTrailingRounded() {
        let info = MenuBarSplitShapeInfo(
            leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
            trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
        )
        XCTAssertTrue(info.hasRoundedShape)
    }

    func testHasRoundedShapeNoneRounded() {
        let info = MenuBarSplitShapeInfo(
            leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
            trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        )
        XCTAssertFalse(info.hasRoundedShape)
    }

    func testCodable() throws {
        let original = MenuBarSplitShapeInfo.defaultValue

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarSplitShapeInfo.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

final class MenuBarSplitPillGeometryTests: XCTestCase {
    func testTrailingBoundsEmptyWhenNoVisibleItems() {
        let rect = CGRect(x: 0, y: 5, width: 1512, height: 37)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let bounds = MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: [],
            in: rect,
            screenFrame: screenFrame,
            leadingOutset: 12,
            trailingOutset: 12,
            notchFrame: nil,
            notchMargin: 8
        )

        XCTAssertEqual(bounds, .zero)
    }

    func testLeadingBoundsClampBeforeNotch() {
        let rect = CGRect(x: 0, y: 5, width: 1512, height: 37)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let appMenuFrame = CGRect(x: 0, y: 945, width: 900, height: 37)
        let notchFrame = CGRect(x: 684, y: 945, width: 144, height: 37)

        let bounds = MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: appMenuFrame,
            trailingContentMinX: nil,
            in: rect,
            screenFrame: screenFrame,
            trailingPadding: 12,
            leadingMargin: 0,
            notchFrame: notchFrame,
            notchMargin: 8
        )

        XCTAssertEqual(bounds.minX, 0)
        XCTAssertEqual(bounds.maxX, 676)
    }

    func testLeadingBoundsFallbackWhenApplicationMenuFrameMissing() {
        let rect = CGRect(x: 0, y: 5, width: 1512, height: 37)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notchFrame = CGRect(x: 684, y: 945, width: 144, height: 37)

        let bounds = MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: .zero,
            trailingContentMinX: nil,
            in: rect,
            screenFrame: screenFrame,
            trailingPadding: 12,
            leadingMargin: 0,
            notchFrame: notchFrame,
            notchMargin: 8
        )

        XCTAssertEqual(bounds.minX, 0)
        XCTAssertEqual(bounds.maxX, 676)
    }

    func testTrailingBoundsClampAfterNotchAndConvertToLocalCoordinates() {
        let rect = CGRect(x: 0, y: 5, width: 1512, height: 37)
        let screenFrame = CGRect(x: 2000, y: 0, width: 1512, height: 982)
        let notchFrame = CGRect(x: 2684, y: 945, width: 144, height: 37)
        let itemBounds = [
            CGRect(x: 2790, y: 945, width: 24, height: 37),
            CGRect(x: 3400, y: 945, width: 80, height: 37),
        ]

        let bounds = MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: itemBounds,
            in: rect,
            screenFrame: screenFrame,
            leadingOutset: 12,
            trailingOutset: 12,
            notchFrame: notchFrame,
            notchMargin: 8
        )

        XCTAssertEqual(bounds.minX, 836)
        XCTAssertEqual(bounds.maxX, 1492)
    }

    func testResolveSplitPathBoundsDoesNotResurrectStaleTrailingOnOverlap() {
        let leading = CGRect(x: 0, y: 0, width: 400, height: 24)
        let overlappingTrailing = CGRect(x: 350, y: 0, width: 200, height: 24)
        let staleTrailing = CGRect(x: 200, y: 0, width: 800, height: 24)

        let resolved = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: leading,
            trailing: overlappingTrailing,
            geometryFrozen: false,
            lastStableLeading: leading,
            lastStableTrailing: staleTrailing
        )

        XCTAssertEqual(resolved.trailing, .zero)
        XCTAssertEqual(resolved.nextStableTrailing, .zero)
    }

    @available(macOS 27, *)
    func testTrailingPillBoundsExcludesHiddenSectionAppleItemsEvenIfNonConcealable() {
        // CC-governable Apple items (Sound, WiFi, …) in Thaw's hidden section sit
        // in the hidden slot far to the left when CC-hidden. They must be excluded
        // by the section filter or the trailing pill stretches left over empty space.
        let hiddenCCItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.apple.controlcenter", title: "Sound"),
            windowID: 1,
            bounds: CGRect(x: 200, y: 3, width: 24, height: 24)
        )
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.apple.systemuiserver", title: "Clock"),
            windowID: 2,
            bounds: CGRect(x: 1450, y: 3, width: 60, height: 24)
        )
        let control = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            bounds: CGRect(x: 1400, y: 3, width: 35, height: 24)
        )
        let items = [hiddenCCItem, control, visible]
        let context = MenuBarSplitPillGeometry.TrailingPillContext(
            revealedSection: nil,
            section: { item in
                item.windowID == 1 ? .hidden : .visible
            }
        )

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            context: context
        )

        // The hidden CC item must not contribute to the bounds.
        XCTAssertFalse(bounds.contains(hiddenCCItem.bounds),
                       "hidden-section CC item should be excluded from trailing pill")
        XCTAssertTrue(bounds.contains(visible.bounds),
                      "visible-section item should be included")
    }

    @available(macOS 27, *)
    func testTrailingPillBoundsIncludesVisibleItemsLeftOfChevron() {
        // Third-party status items can legitimately sit left of Thaw's chevron.
        // The chevron position is not a visibility boundary.
        let istatItem = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus.status", title: "iStat"),
            windowID: 1,
            bounds: CGRect(x: 300, y: 3, width: 24, height: 24)
        )
        let istatItem2 = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus.status", title: "iStat-2"),
            windowID: 2,
            bounds: CGRect(x: 330, y: 3, width: 24, height: 24)
        )
        let istatItem3 = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.bjango.istatmenus.status", title: "iStat-3"),
            windowID: 3,
            bounds: CGRect(x: 360, y: 3, width: 24, height: 24)
        )
        let chevron = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            bounds: CGRect(x: 1150, y: 3, width: 35, height: 24)
        )
        let clock = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.apple.systemuiserver", title: "Clock"),
            windowID: 200,
            bounds: CGRect(x: 1420, y: 3, width: 60, height: 24)
        )
        let items = [istatItem, istatItem2, istatItem3, chevron, clock]
        let context = MenuBarSplitPillGeometry.TrailingPillContext(
            revealedSection: nil,
            section: { _ in .visible }
        )

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            context: context
        )

        XCTAssertTrue(bounds.contains(istatItem.bounds), "visible item left of chevron should be included")
        XCTAssertTrue(bounds.contains(istatItem2.bounds), "visible item left of chevron should be included")
        XCTAssertTrue(bounds.contains(istatItem3.bounds), "visible item left of chevron should be included")
        XCTAssertTrue(bounds.contains(clock.bounds), "visible item right of chevron should be included")
        XCTAssertTrue(bounds.contains(chevron.bounds), "visible control item should be included")
    }

    func testResolveSplitPathBoundsReturnsBothZeroWhenNoGeometryYet() {
        // When no geometry is loaded yet (startup), resolve should return (.zero, .zero)
        // so the caller draws nothing rather than a full-width fallback pill.
        let resolved = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: .zero,
            trailing: .zero,
            geometryFrozen: false,
            lastStableLeading: .zero,
            lastStableTrailing: .zero
        )

        XCTAssertEqual(resolved.leading, .zero)
        XCTAssertEqual(resolved.trailing, .zero)
    }

    func testResolveSplitPathBoundsRestoresStablePairWhenFrozen() {
        let leading = CGRect(x: 0, y: 0, width: 400, height: 24)
        let trailing = CGRect(x: 500, y: 0, width: 200, height: 24)
        let freshLeading = CGRect(x: 10, y: 0, width: 50, height: 24)

        let resolved = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: freshLeading,
            trailing: .zero,
            geometryFrozen: true,
            lastStableLeading: leading,
            lastStableTrailing: trailing
        )

        XCTAssertEqual(resolved.leading, leading)
        XCTAssertEqual(resolved.trailing, trailing)
    }

    @available(macOS 27, *)
    func testTrailingPillBoundsExcludesParkedItems() {
        let control = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            bounds: CGRect(x: 1200, y: 3, width: 35, height: 24)
        )
        let onBar = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Item"),
            windowID: 1,
            bounds: CGRect(x: 1250, y: 3, width: 24, height: 24)
        )
        let parked = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.other.app", title: "Parked"),
            windowID: 2,
            bounds: CGRect(x: 7, y: 1413, width: 21, height: 24)
        )
        let items = [control, onBar, parked]
        let context = MenuBarSplitPillGeometry.TrailingPillContext(
            revealedSection: nil,
            section: { _ in .visible }
        )

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            context: context
        )

        XCTAssertEqual(bounds.count, 2)
        XCTAssertTrue(bounds.contains(control.bounds), "visible control item should be included")
        XCTAssertTrue(bounds.contains(onBar.bounds), "on-bar item should be included")
        XCTAssertFalse(bounds.contains(parked.bounds), "parked item should be excluded")
    }

    @available(macOS 27, *)
    func testTrailingPillBoundsExcludesConcealedHiddenSectionGhosts() {
        let ghost = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.hidden.app", title: "Ghost"),
            windowID: 1,
            bounds: CGRect(x: 900, y: 3, width: 24, height: 24)
        )
        let visible = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.visible.app", title: "Visible"),
            windowID: 2,
            bounds: CGRect(x: 1250, y: 3, width: 24, height: 24)
        )
        let control = MenuBarItem.fixture(
            tag: .visibleControlItem,
            windowID: 100,
            bounds: CGRect(x: 1200, y: 3, width: 35, height: 24)
        )
        let items = [ghost, control, visible]
        let context = MenuBarSplitPillGeometry.TrailingPillContext(
            revealedSection: nil,
            section: { item in
                item.tag.title == "Ghost" ? .hidden : .visible
            }
        )

        let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
            from: items,
            context: context
        )

        XCTAssertEqual(bounds.count, 2)
        XCTAssertTrue(bounds.contains(control.bounds), "visible control item should be included")
        XCTAssertTrue(bounds.contains(visible.bounds), "visible item should be included")
        XCTAssertFalse(bounds.contains(ghost.bounds), "concealed hidden-section ghost should be excluded")
    }
}

// MARK: - MenuBarNotchShapeInfo Tests

final class MenuBarNotchShapeInfoTests: XCTestCase {
    func testDefaultValue() {
        let defaultInfo = MenuBarNotchShapeInfo.defaultValue
        XCTAssertEqual(defaultInfo.leading, MenuBarFullShapeInfo.defaultValue)
        XCTAssertEqual(defaultInfo.trailing, MenuBarFullShapeInfo.defaultValue)
    }

    func testHasRoundedShapeLeadingRounded() {
        let info = MenuBarNotchShapeInfo(
            leading: MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .square),
            trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        )
        XCTAssertTrue(info.hasRoundedShape)
    }

    func testHasRoundedShapeTrailingRounded() {
        let info = MenuBarNotchShapeInfo(
            leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
            trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .round)
        )
        XCTAssertTrue(info.hasRoundedShape)
    }

    func testHasRoundedShapeNoneRounded() {
        let info = MenuBarNotchShapeInfo(
            leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
            trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        )
        XCTAssertFalse(info.hasRoundedShape)
    }

    func testCodable() throws {
        let original = MenuBarNotchShapeInfo.defaultValue

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MenuBarNotchShapeInfo.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testHashable() {
        let info1 = MenuBarNotchShapeInfo.defaultValue
        let info2 = MenuBarNotchShapeInfo.defaultValue
        let info3 = MenuBarNotchShapeInfo(
            leading: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square),
            trailing: MenuBarFullShapeInfo(leadingEndCap: .square, trailingEndCap: .square)
        )

        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
    }

    func testShapeKindCodableNotch() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(MenuBarShapeKind.notch)
        let decoded = try decoder.decode(MenuBarShapeKind.self, from: data)
        XCTAssertEqual(decoded, .notch)
    }
}
