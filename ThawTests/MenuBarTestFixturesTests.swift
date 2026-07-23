//
//  MenuBarTestFixturesTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarHost
import PlatformRuntimeKit
@testable import Thaw
import XCTest

final class HIDEventManagerHoverPermissionTests: XCTestCase {
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
    func testSupportedAddTargetTypeEncodings() {
        XCTAssertTrue(ControlItem.isSupportedAddTargetTypeEncoding("v@:@:Q"))
        XCTAssertTrue(ControlItem.isSupportedAddTargetTypeEncoding("v40@0:8@16:24Q32"))
        XCTAssertFalse(ControlItem.isSupportedAddTargetTypeEncoding("v@:"))
    }

    func testMenuBarAgentLayoutNudgeUsesRenderedWidthForVariableStatusItem() {
        XCTAssertEqual(
            ControlItem.menuBarAgentLayoutNudgeLength(
                currentLength: NSStatusItem.variableLength,
                renderedWidth: 35
            ),
            35
        )
    }

    func testMenuBarAgentLayoutNudgePerturbsAlreadyFixedWidth() {
        XCTAssertEqual(
            ControlItem.menuBarAgentLayoutNudgeLength(
                currentLength: 35,
                renderedWidth: 35
            ),
            35.5
        )
    }

    func testMenuBarAgentLayoutNudgeRejectsMissingRenderedWidth() {
        XCTAssertNil(
            ControlItem.menuBarAgentLayoutNudgeLength(
                currentLength: NSStatusItem.variableLength,
                renderedWidth: 0
            )
        )
    }

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

    func testFreshBoundsCoverVisibleAndRevealedSections() {
        XCTAssertTrue(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .hidden,
                revealedSection: .hidden
            )
        )
        XCTAssertTrue(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .hidden,
                revealedSection: .alwaysHidden
            )
        )
        XCTAssertTrue(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .alwaysHidden,
                revealedSection: .alwaysHidden
            )
        )
        XCTAssertFalse(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .alwaysHidden,
                revealedSection: .hidden
            )
        )
        // Visible items stay on-screen during Always Hidden reveal; fresh
        // bounds are only required for sections that were just un-concealed.
        XCTAssertFalse(
            MenuBarItemImageCache.shouldUseFreshBounds(
                for: .visible,
                revealedSection: .alwaysHidden
            )
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
        let legacy = HostMenuBarBackend()
        let assertion = RuntimeMenuBarBackend()

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

    @MainActor
    func testCapturedImageReusesHorizontallyTrimmedSearchImage() throws {
        let image = try makeImage(alpha: 255)
        let captured = MenuBarItemImageCache.CapturedImage(cgImage: image, scale: 2)

        let first = try XCTUnwrap(captured.horizontallyTrimmedImage)
        let second = try XCTUnwrap(captured.horizontallyTrimmedImage)

        XCTAssertTrue(first === second)
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
        let image = try makeImage(alpha: 255, width: 48, height: 44)
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
        let image = try makeImage(alpha: 0, width: 48, height: 44)
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

    func testPrewarmNeedsCaptureWhenCachedImageIsChevronNarrow() throws {
        let image = try makeImage(alpha: 255, width: 20, height: 44)
        let captured = MenuBarItemImageCache.CapturedImage(cgImage: image, scale: 2)
        XCTAssertLessThan(captured.scaledSize.width, MenuBarItemImageCache.minimumTrustedGlyphWidth)

        XCTAssertTrue(
            MenuBarItemImageCache.prewarmNeedsCapture(
                cachedImage: captured,
                wouldAttemptCapture: true
            )
        )
    }

    @MainActor
    func testPreferredCachedImageKeepsSettledGlyphOverNarrowerCandidate() throws {
        let settled = try MenuBarItemImageCache.CapturedImage(
            cgImage: makeImage(alpha: 255, width: 48, height: 44),
            scale: 2
        )
        let chevronBleed = try MenuBarItemImageCache.CapturedImage(
            cgImage: makeImage(alpha: 255, width: 20, height: 44),
            scale: 2
        )

        let preferred = MenuBarItemImageCache.preferredCachedImage(
            existing: settled,
            candidate: chevronBleed
        )
        XCTAssertTrue(
            MenuBarItemImageCache.CapturedImage.isVisuallyEqual(preferred, settled)
        )
    }

    @MainActor
    func testPreferredCachedImageKeepsSettledGlyphOverBlankCandidate() throws {
        let settled = try MenuBarItemImageCache.CapturedImage(
            cgImage: makeImage(alpha: 255, width: 48, height: 44),
            scale: 2
        )
        let blank = try MenuBarItemImageCache.CapturedImage(
            cgImage: makeImage(alpha: 0, width: 48, height: 44),
            scale: 2
        )

        let preferred = MenuBarItemImageCache.preferredCachedImage(
            existing: settled,
            candidate: blank
        )
        XCTAssertTrue(
            MenuBarItemImageCache.CapturedImage.isVisuallyEqual(preferred, settled)
        )
    }

    @MainActor
    func testPreferredCachedImageAcceptsWiderCandidate() throws {
        let narrow = try MenuBarItemImageCache.CapturedImage(
            cgImage: makeImage(alpha: 255, width: 20, height: 44),
            scale: 2
        )
        let wider = try MenuBarItemImageCache.CapturedImage(
            cgImage: makeImage(alpha: 255, width: 48, height: 44),
            scale: 2
        )

        let preferred = MenuBarItemImageCache.preferredCachedImage(
            existing: narrow,
            candidate: wider
        )
        XCTAssertTrue(
            MenuBarItemImageCache.CapturedImage.isVisuallyEqual(preferred, wider)
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

    private func makeImage(alpha: UInt8, width: Int = 2, height: Int = 2) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) {
            pixels[index] = alpha
            if alpha > 0 {
                pixels[index - 3] = 255
                pixels[index - 2] = 255
                pixels[index - 1] = 255
            }
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
