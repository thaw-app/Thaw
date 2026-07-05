//
//  MenuBarTestFixturesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Sanity tests for the synthetic fixture builders in
/// MenuBarTestFixtures.swift. These pin down that the fixtures produce values
/// with the documented defaults so the planner tests built on top of them stay
/// stable.
final class MenuBarTestFixturesTests: XCTestCase {
    func testHoverPermissionBlocksRevealWhileSectionIsHidden() {
        XCTAssertFalse(
            HIDEventManager.shouldProcessHover(
                showOnHover: true,
                showOnHoverAllowed: false,
                sectionIsHidden: true
            )
        )
    }

    func testHoverPermissionDoesNotBlockConcealWhileSectionIsVisible() {
        XCTAssertTrue(
            HIDEventManager.shouldProcessHover(
                showOnHover: true,
                showOnHoverAllowed: false,
                sectionIsHidden: false
            )
        )
    }

    func testAppItemTagBuildsExpectedNamespaceAndTitle() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        XCTAssertEqual(String(describing: tag.namespace), "com.example.app")
        XCTAssertEqual(tag.title, "Status")
        XCTAssertEqual(tag.instanceIndex, 0)
        XCTAssertNil(tag.windowID)
    }

    func testAppItemTagSupportsInstanceIndex() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status", instanceIndex: 2)
        XCTAssertEqual(tag.instanceIndex, 2)
    }

    func testMenuBarItemFixtureDefaultsToMovableHideableItem() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        let item = MenuBarItem.fixture(tag: tag, windowID: 42)

        XCTAssertEqual(item.windowID, 42)
        XCTAssertEqual(item.tag, tag)
        XCTAssertEqual(item.sourcePID, 1234)
        XCTAssertEqual(item.ownerPID, 1234)
        XCTAssertEqual(item.bounds, CGRect(x: 0, y: 0, width: 24, height: 22))
        XCTAssertTrue(item.isMovable)
        XCTAssertTrue(item.canBeHidden)
        XCTAssertFalse(item.isControlItem)
        XCTAssertTrue(item.isOnScreen)
    }

    func testMenuBarItemFixtureRespectsExplicitBounds() {
        let bounds = CGRect(x: 100, y: 0, width: 30, height: 22)
        let item = MenuBarItem.fixture(
            tag: .appItem(bundleID: "com.example.app", title: "Status"),
            windowID: 1,
            bounds: bounds
        )
        XCTAssertEqual(item.bounds, bounds)
    }

    func testControlItemPairFixtureWithoutAlwaysHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22)
        )

        XCTAssertEqual(pair.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(pair.hidden.bounds.minX, 500)
        XCTAssertNil(pair.alwaysHidden)
    }

    func testControlItemPairFixtureWithAlwaysHidden() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )

        XCTAssertEqual(pair.hidden.tag, .hiddenControlItem)
        XCTAssertEqual(pair.alwaysHidden?.tag, .alwaysHiddenControlItem)
        XCTAssertEqual(pair.alwaysHidden?.bounds.minX, 200)
    }

    func testControlItemPairFixtureWindowIDsAreDistinct() {
        let pair = MenuBarItemManager.ControlItemPair.fixture(
            hiddenAt: CGRect(x: 500, y: 0, width: 24, height: 22),
            alwaysHiddenAt: CGRect(x: 200, y: 0, width: 24, height: 22)
        )
        XCTAssertNotEqual(pair.hidden.windowID, pair.alwaysHidden?.windowID)
    }
}

// MARK: - ControlItemDefaults Tests

final class ControlItemDefaultsTests: XCTestCase {
    private let visibleAutosaveName = ControlItem.Identifier.visible.rawValue

    override func tearDown() {
        ControlItemDefaults[.visible, visibleAutosaveName] = nil
        ControlItemDefaults[.visibleCC, visibleAutosaveName] = nil
        ControlItemDefaults[.preferredPosition, visibleAutosaveName] = nil
        super.tearDown()
    }

    func testRestoreVisibilityForVisibleControlItemRepairsPersistedHiddenStateOnMacOS27() {
        ControlItemDefaults[.visible, visibleAutosaveName] = false
        ControlItemDefaults[.visibleCC, visibleAutosaveName] = false

        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: visibleAutosaveName)

        if #available(macOS 27, *) {
            XCTAssertEqual(ControlItemDefaults[.visible, visibleAutosaveName], true)
            XCTAssertEqual(ControlItemDefaults[.visibleCC, visibleAutosaveName], true)
        } else {
            XCTAssertEqual(ControlItemDefaults[.visible, visibleAutosaveName], false)
            XCTAssertEqual(ControlItemDefaults[.visibleCC, visibleAutosaveName], false)
        }
    }

    func testRestoreVisibilityRepairsHiddenSectionDividerOnMacOS27() {
        let hiddenAutosaveName = ControlItem.Identifier.hidden.rawValue
        ControlItemDefaults[.visible, hiddenAutosaveName] = false
        ControlItemDefaults[.visibleCC, hiddenAutosaveName] = false
        defer {
            ControlItemDefaults[.visible, hiddenAutosaveName] = nil
            ControlItemDefaults[.visibleCC, hiddenAutosaveName] = nil
        }

        ControlItemDefaults.restoreVisibilityIfNeeded(autosaveName: hiddenAutosaveName)

        if #available(macOS 27, *) {
            XCTAssertEqual(ControlItemDefaults[.visible, hiddenAutosaveName], true)
            XCTAssertEqual(ControlItemDefaults[.visibleCC, hiddenAutosaveName], true)
        } else {
            XCTAssertEqual(ControlItemDefaults[.visible, hiddenAutosaveName], false)
            XCTAssertEqual(ControlItemDefaults[.visibleCC, hiddenAutosaveName], false)
        }
    }

    func testMacOS27VisibleControlItemDoesNotRestoreCachedPreferredPositionAfterRemoval() {
        let shouldRestore = ControlItemDefaults.shouldRestorePreferredPositionAfterRemoval(
            autosaveName: visibleAutosaveName,
            isSectionDivider: false
        )

        if #available(macOS 27, *) {
            XCTAssertFalse(shouldRestore)
        } else {
            XCTAssertTrue(shouldRestore)
        }
    }

    func testSectionDividerDoesNotRestoreCachedPreferredPositionAfterRemoval() {
        let shouldRestore = ControlItemDefaults.shouldRestorePreferredPositionAfterRemoval(
            autosaveName: ControlItem.Identifier.hidden.rawValue,
            isSectionDivider: true
        )

        XCTAssertFalse(shouldRestore)
    }
}

// MARK: - ControlItem Section Divider Tests

final class ControlItemSectionDividerTests: XCTestCase {
    func testMacOS27ConcealedSectionCollapsesDividerUntilReveal() {
        let presentation = ControlItem.sectionDividerPresentation(
            state: .hideSection,
            style: .chevron,
            supportsSectionHiding: false
        )

        XCTAssertEqual(presentation, .hidden)
    }

    func testMacOS27NoDividerCollapsesConcealedSectionDivider() {
        let presentation = ControlItem.sectionDividerPresentation(
            state: .hideSection,
            style: .noDivider,
            supportsSectionHiding: false
        )

        XCTAssertEqual(presentation, .hidden)
    }

    func testLegacyConcealedSectionRetainsExpandedInvisibleDivider() {
        let presentation = ControlItem.sectionDividerPresentation(
            state: .hideSection,
            style: .chevron,
            supportsSectionHiding: true
        )

        XCTAssertEqual(presentation, .legacyConcealedSection)
    }

    func testRevealedSectionUsesConfiguredDividerStyle() {
        XCTAssertEqual(
            ControlItem.sectionDividerPresentation(
                state: .showSection,
                style: .chevron,
                supportsSectionHiding: true
            ),
            .chevron
        )
        XCTAssertEqual(
            ControlItem.sectionDividerPresentation(
                state: .showSection,
                style: .noDivider,
                supportsSectionHiding: false
            ),
            .hidden
        )
    }
}

// MARK: - ControlItem Primary Action Tests

final class ControlItemPrimaryActionTests: XCTestCase {
    func testPlainPrimaryActionTogglesSection() {
        XCTAssertEqual(primaryAction(), .toggleSection)
    }

    func testKeyboardPrimaryActionTogglesSection() {
        XCTAssertEqual(primaryAction(clickCount: 0), .toggleSection)
    }

    func testControlPrimaryActionDefersToContextMenu() {
        XCTAssertEqual(primaryAction(modifierFlags: .control), .contextMenu)
    }

    func testOptionPrimaryActionTogglesAlwaysHiddenSectionWhenEnabled() {
        XCTAssertEqual(
            primaryAction(modifierFlags: .option, usesOptionClick: true),
            .toggleAlwaysHidden
        )
    }

    func testOptionPrimaryActionDoesNothingWhenDisabled() {
        XCTAssertEqual(primaryAction(modifierFlags: .option), .none)
    }

    func testDoublePrimaryActionShowsAlwaysHiddenSectionWhenEnabled() {
        XCTAssertEqual(
            primaryAction(clickCount: 2, usesDoubleClick: true),
            .showAlwaysHidden
        )
    }

    func testDoublePrimaryActionUsesNormalBehaviorWhenDisabled() {
        XCTAssertEqual(primaryAction(clickCount: 2), .toggleSection)
    }

    func testMenuBarAgentPrimaryActionIgnoresControlModifier() {
        XCTAssertEqual(
            menuBarAgentPrimaryAction(modifierFlags: .control),
            .toggleSection
        )
    }

    func testMenuBarAgentPrimaryActionKeepsOptionAndDoubleClickBehavior() {
        XCTAssertEqual(
            menuBarAgentPrimaryAction(modifierFlags: .option, usesOptionClick: true),
            .toggleAlwaysHidden
        )
        XCTAssertEqual(
            menuBarAgentPrimaryAction(clickCount: 2, usesDoubleClick: true),
            .showAlwaysHidden
        )
    }

    private func primaryAction(
        modifierFlags: NSEvent.ModifierFlags = [],
        clickCount: Int = 1,
        usesDoubleClick: Bool = false,
        usesOptionClick: Bool = false
    ) -> ControlItem.PrimaryActionIntent {
        ControlItem.primaryActionIntent(
            identifier: .visible,
            modifierFlags: modifierFlags,
            clickCount: clickCount,
            usesDoubleClick: usesDoubleClick,
            usesOptionClick: usesOptionClick
        )
    }

    private func menuBarAgentPrimaryAction(
        modifierFlags: NSEvent.ModifierFlags = [],
        clickCount: Int = 1,
        usesDoubleClick: Bool = false,
        usesOptionClick: Bool = false
    ) -> ControlItem.PrimaryActionIntent {
        ControlItem.menuBarAgentPrimaryActionIntent(
            identifier: .visible,
            modifierFlags: modifierFlags,
            clickCount: clickCount,
            usesDoubleClick: usesDoubleClick,
            usesOptionClick: usesOptionClick
        )
    }
}

// MARK: - Control Item Context Menu Routing Tests

final class ControlItemContextMenuRoutingTests: XCTestCase {
    private let iconFrame = CGRect(x: 100, y: 900, width: 24, height: 24)

    func testMacOS27RoutesClickInsideIconToControlItemMenu() {
        XCTAssertTrue(
            HIDEventManager.shouldShowControlItemContextMenu(
                usesMenuBarAgent: true,
                controlItemFrame: iconFrame,
                clickLocation: CGPoint(x: 112, y: 912)
            )
        )
    }

    func testMacOS27LeavesClickOutsideIconForMenuBarContextMenu() {
        XCTAssertFalse(
            HIDEventManager.shouldShowControlItemContextMenu(
                usesMenuBarAgent: true,
                controlItemFrame: iconFrame,
                clickLocation: CGPoint(x: 80, y: 912)
            )
        )
    }

    func testLegacySystemDoesNotUseGlobalControlItemMenuRoute() {
        XCTAssertFalse(
            HIDEventManager.shouldShowControlItemContextMenu(
                usesMenuBarAgent: false,
                controlItemFrame: iconFrame,
                clickLocation: CGPoint(x: 112, y: 912)
            )
        )
    }

    func testMissingControlItemFrameDoesNotConsumeClick() {
        XCTAssertFalse(
            HIDEventManager.shouldShowControlItemContextMenu(
                usesMenuBarAgent: true,
                controlItemFrame: nil,
                clickLocation: CGPoint(x: 112, y: 912)
            )
        )
    }
}

// MARK: - Menu Bar Item Capture Section Tests

final class MenuBarItemCaptureSectionTests: XCTestCase {
    private let allSections = MenuBarSection.Name.allCases

    func testLegacyCaptureKeepsEveryRequestedSection() {
        XCTAssertEqual(
            capturableSections(usesVisibilityRestrictions: false, revealedSection: nil),
            allSections
        )
    }

    func testMacOS27ConcealedCaptureUsesOnlyVisibleSection() {
        XCTAssertEqual(
            capturableSections(usesVisibilityRestrictions: true, revealedSection: nil),
            [.visible]
        )
    }

    func testMacOS27HiddenRevealCapturesVisibleAndHiddenSections() {
        XCTAssertEqual(
            capturableSections(usesVisibilityRestrictions: true, revealedSection: .hidden),
            [.visible, .hidden]
        )
    }

    func testMacOS27AlwaysHiddenRevealCapturesEverySection() {
        XCTAssertEqual(
            capturableSections(usesVisibilityRestrictions: true, revealedSection: .alwaysHidden),
            allSections
        )
    }

    func testCaptureDisplayPrefersItemCacheDisplay() {
        XCTAssertEqual(
            MenuBarItemImageCache.captureDisplayID(
                itemCacheDisplayID: 42,
                activeMenuBarDisplayID: 7,
                mainDisplayID: 1
            ),
            42
        )
    }

    private func capturableSections(
        usesVisibilityRestrictions: Bool,
        revealedSection: MenuBarSection.Name?
    ) -> [MenuBarSection.Name] {
        MenuBarItemImageCache.capturableSections(
            from: allSections,
            usesVisibilityRestrictions: usesVisibilityRestrictions,
            revealedSection: revealedSection
        )
    }

    func testBackendAdaptersExposeDistinctSectionModels() {
        let legacy = LegacyMenuBarBackend()
        let assertion = AssertionMenuBarBackend()

        XCTAssertTrue(legacy.supportsLegacySectionHiding)
        XCTAssertFalse(legacy.usesAssertionHiding)
        XCTAssertFalse(assertion.supportsLegacySectionHiding)
        XCTAssertTrue(assertion.usesAssertionHiding)
        XCTAssertEqual(
            legacy.capturableSections(from: allSections, revealedSection: nil),
            allSections
        )
        XCTAssertEqual(
            assertion.capturableSections(from: allSections, revealedSection: nil),
            [.visible]
        )
    }
}

// MARK: - Image Capture Invalidation Tests

final class ImageCaptureInvalidationTests: XCTestCase {
    func testTransparentCapturedImageIsEffectivelyBlank() throws {
        let image = try makeImage(alpha: 0)
        let captured = MenuBarItemImageCache.CapturedImage(cgImage: image, scale: 2)
        XCTAssertTrue(captured.isEffectivelyBlank)
    }

    func testOpaqueCapturedImageIsNotEffectivelyBlank() throws {
        let image = try makeImage(alpha: 255)
        let captured = MenuBarItemImageCache.CapturedImage(cgImage: image, scale: 2)
        XCTAssertFalse(captured.isEffectivelyBlank)
    }

    func testPrewarmRevealRestorationHidesWhenPrewarmCreatedReveal() {
        XCTAssertEqual(
            MenuBarItemImageCache.PrewarmRevealRestorationAction.resolve(
                previous: nil,
                currentAfterShow: .hidden
            ),
            .hide
        )
    }

    func testPrewarmRevealRestorationNoOpsWhenRevealAlreadyOpen() {
        XCTAssertEqual(
            MenuBarItemImageCache.PrewarmRevealRestorationAction.resolve(
                previous: .hidden,
                currentAfterShow: .hidden
            ),
            .noOp
        )
    }

    func testPrewarmRevealRestorationRestoresPreviousReveal() {
        XCTAssertEqual(
            MenuBarItemImageCache.PrewarmRevealRestorationAction.resolve(
                previous: .alwaysHidden,
                currentAfterShow: .hidden
            ),
            .show(.alwaysHidden)
        )
    }

    func testPrewarmNeedsCaptureWhenImageMissing() throws {
        let image = try makeImage(alpha: 255)
        let captured = MenuBarItemImageCache.CapturedImage(cgImage: image, scale: 2)

        XCTAssertTrue(
            MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: nil,
                wouldAttemptCapture: true
            )
        )
        XCTAssertFalse(
            MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: captured,
                wouldAttemptCapture: true
            )
        )
    }

    func testPrewarmNeedsCaptureWhenImageBlank() throws {
        let image = try makeImage(alpha: 0)
        let captured = MenuBarItemImageCache.CapturedImage(cgImage: image, scale: 2)

        XCTAssertTrue(
            MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: captured,
                wouldAttemptCapture: true
            )
        )
        XCTAssertFalse(
            MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: captured,
                wouldAttemptCapture: false
            )
        )
    }

    func testPositionOnlyJitterDoesNotInvalidateCapture() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        let original = cache(containing: .fixture(
            tag: tag,
            windowID: 100,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22)
        ))
        let jittered = cache(containing: .fixture(
            tag: tag,
            windowID: 100,
            bounds: CGRect(x: 101, y: 1, width: 24, height: 22)
        ))

        XCTAssertEqual(
            MenuBarItemImageCache.captureInvalidationKey(original),
            MenuBarItemImageCache.captureInvalidationKey(jittered)
        )
    }

    func testSizeChangeInvalidatesCapture() {
        let tag = MenuBarItemTag.appItem(bundleID: "com.example.app", title: "Status")
        let original = cache(containing: .fixture(
            tag: tag,
            windowID: 100,
            bounds: CGRect(x: 100, y: 0, width: 24, height: 22)
        ))
        let resized = cache(containing: .fixture(
            tag: tag,
            windowID: 100,
            bounds: CGRect(x: 100, y: 0, width: 30, height: 22)
        ))

        XCTAssertNotEqual(
            MenuBarItemImageCache.captureInvalidationKey(original),
            MenuBarItemImageCache.captureInvalidationKey(resized)
        )
    }

    private func cache(containing item: MenuBarItem) -> MenuBarItemManager.ItemCache {
        var cache = MenuBarItemManager.ItemCache(displayID: 1)
        cache[.visible] = [item]
        return cache
    }

    private func makeImage(alpha: UInt8) throws -> CGImage {
        let width = 2
        let height = 2
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) {
            pixels[index] = alpha
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw XCTSkip("Unable to create test image")
        }
        return image
    }
}
