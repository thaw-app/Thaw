//
//  MenuBarItemImageCache+Reading.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawCapture

extension MenuBarItemImageCache {
    // MARK: Reading Pixels

    /// Checks which of the given items currently render as blank pixels in the
    /// real menu bar, independent of this cache's own stored images.
    ///
    /// A restriction reflow can leave an item hit-testable but undrawn, and the
    /// cache often has no entry for visible items, so only a fresh screenshot
    /// shows whether the OS redrew the glyph.
    nonisolated func itemsRenderingBlank(
        among items: [MenuBarItem],
        displayID: CGDirectDisplayID
    ) async -> Set<MenuBarItemTag> {
        guard !items.isEmpty else { return [] }

        guard let capture = await ScreenCapture.captureMenuBarHostingWindowAsync(displayID: displayID) else {
            return []
        }
        return Self.blankTags(in: items, from: capture)
    }

    static nonisolated func blankTags(
        in items: [MenuBarItem],
        from capture: ScreenCapture.MenuBarHostingCapture
    ) -> Set<MenuBarItemTag> {
        let composite = capture.image

        var blankTags = Set<MenuBarItemTag>()
        for item in items {
            guard capture.windowFrame.intersects(item.bounds),
                  let mapping = capture.cropMapping(forItemBounds: item.bounds),
                  !mapping.clamped.isNull, !mapping.clamped.isEmpty,
                  let croppedImage = composite.cropping(to: mapping.clamped)
            else {
                continue
            }
            if croppedImage.isTransparent() {
                blankTags.insert(item.tag)
            }
        }
        return blankTags
    }

    /// One capture's reading of the items it was asked about.
    ///
    /// A tag in neither set was undecidable (outside the frame, or not
    /// separable from its background), which is not the same as blank.
    struct CaptureVerdict {
        /// The tags that rendered pixels.
        var seen = Set<MenuBarItemTag>()

        /// The tags that rendered nothing.
        var blank = Set<MenuBarItemTag>()
    }

    /// Reads items out of capture, saying for each one whether it rendered.
    ///
    /// Unlike blankTags(in:from:) this separates "rendered nothing" from
    /// "this capture cannot say".
    ///
    /// - Parameter knockingOutBackground: Pass true for a display-strip
    ///   capture, whose empty slots are opaque bar fill rather than
    ///   transparent. Hosting-window crops are already transparent.
    static nonisolated func verdict(
        for items: [MenuBarItem],
        from capture: ScreenCapture.MenuBarHostingCapture,
        knockingOutBackground: Bool
    ) -> CaptureVerdict {
        let composite = capture.image

        var verdict = CaptureVerdict()
        for item in items {
            // Containment, not intersection: a clipped frame renders short and
            // the shortfall looks like absence.
            guard capture.windowFrame.contains(item.bounds),
                  let mapping = capture.cropMapping(forItemBounds: item.bounds),
                  !mapping.clamped.isNull, !mapping.clamped.isEmpty,
                  let rawCrop = composite.cropping(to: mapping.clamped)
            else {
                continue
            }

            guard knockingOutBackground else {
                if rawCrop.isTransparent() {
                    verdict.blank.insert(item.tag)
                } else {
                    verdict.seen.insert(item.tag)
                }
                continue
            }

            switch rawCrop.glyphPresenceOverNearUniformBackground() {
            case .present:
                verdict.seen.insert(item.tag)
            case .absent:
                verdict.blank.insert(item.tag)
            case .indeterminate:
                // Not separable from the wallpaper, so no answer either way.
                continue
            }
        }
        return verdict
    }

    /// Dividers capture as transparent; the visible Thaw icon crops from the
    /// display strip like any Liquid Glass item, except while it is hidden and
    /// collapsed to a sliver that draws nothing. The recording indicator is
    /// excluded because capturing it shows it, which triggers a recapture.
    static nonisolated func isCapturable(_ item: MenuBarItem) -> Bool {
        (!item.isControlItem || (item.tag == .visibleControlItem && item.bounds.width > 2))
            && !item.isTransientControlCenterItem
            && !item.tag.isCaptureActivityIndicator
    }

    @concurrent
    nonisolated func captureImages(
        of items: [MenuBarItem],
        scale _: CGFloat,
        appState: AppState,
        freshBounds: Bool = false,
        concealedIdentifiers: Set<String> = [],
        forgivenTags: Set<MenuBarItemTag> = [],
        geometryOwners: Set<pid_t> = []
    ) async -> CapturePass {
        let capturable = items.filter(Self.isCapturable)

        // A bar mid-reflow draws items scaled down and faded. Bounded so a
        // flag that never clears cannot starve capture.
        let reflowSkip = await MainActor.run { () -> Int in
            let reflowing = appState.barSettling.hold(for: .agentNudge) != nil
            guard Self.skipsPassForReflow(reflowing: reflowing, consecutiveSkips: consecutiveReflowSkips) else {
                consecutiveReflowSkips = 0
                return 0
            }
            consecutiveReflowSkips += 1
            return consecutiveReflowSkips
        }
        if reflowSkip > 0 {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: skipping pass (\(reflowSkip)/\(Self.maximumReflowSkips)); " +
                    "reveal/hide reflow still settling"
            )
            return CapturePass()
        }

        // macOS 27 items have no real CGWindowIDs, so crop AX bounds from the
        // hosting window or the display strip (Liquid Glass shreds under SCK).
        let displayID = await MainActor.run {
            Self.captureDisplayID(
                itemCacheDisplayID: appState.itemManager.itemDisplayID,
                activeMenuBarDisplayID: windowServer.activeMenuBarDisplayID(),
                mainDisplayID: CGMainDisplayID()
            )
        }
        let screenFrame = await MainActor.run {
            NSScreen.screen(for: displayID)?.frame
        }

        return await boundsCropper.crop(
            capturable,
            on: displayID,
            screenFrame: screenFrame,
            options: AXBoundsCropper.Options(freshBounds: freshBounds, concealedIdentifiers: concealedIdentifiers, forgivenTags: forgivenTags),
            using: LiveMenuBarCaptureReader(geometryOwners: geometryOwners),
            skipping: { self.shouldSkipCapture(for: $0) }
        )
    }

    /// Who is going to look at the pixels a pass is about to read.
    ///
    /// Gathered on the main actor once per pass.
    struct CaptureDemand {
        /// The state of "Use app icons instead of live previews".
        let usesAppIcons: Bool
        /// Whether search or the item hotkey list is up. Both read captures
        /// directly and ignore the app-icon preference.
        let hasUnfilteredConsumer: Bool
        /// Items the alert-reveal watcher compares capture to capture, so they
        /// are captured whatever the preference says.
        let alertRevealIdentifiers: Set<String>
    }

    @MainActor
    private func captureDemand() -> CaptureDemand {
        let nav = makeNavigationStateSnapshot()
        return CaptureDemand(
            usesAppIcons: configuration.alwaysUseAppIconForMenuBarItems,
            hasUnfilteredConsumer: nav.isSearchPresented || nav.isItemHotkeyListExpanded,
            alertRevealIdentifiers: MenuBarItemAlertReveals.identifiers()
        )
    }

    /// Narrows a section's items to the ones some surface will actually draw.
    ///
    /// With the app-icon preference on, only Apple's modules (no per-module
    /// icon) and items with no usable app icon still need captures.
    static nonisolated func itemsNeedingCapture(
        _ items: [MenuBarItem],
        demand: CaptureDemand
    ) -> [MenuBarItem] {
        guard demand.usesAppIcons, !demand.hasUnfilteredConsumer else {
            return items
        }
        return items.filter { item in
            OverflowFallbackIcon.usesCapturedSystemPreview(item)
                || !OverflowFallbackIcon.canRenderAppIconWithoutCapture(for: item)
                || demand.alertRevealIdentifiers.contains(item.tag.tagIdentifier)
        }
    }

    /// Captures the images of the menu bar items in the given section.
    func captureImages(
        for section: MenuBarSection.Name,
        scale: CGFloat,
        appState: AppState
    ) async -> CapturePass {
        let items = Self.itemsNeedingCapture(
            appState.itemManager.managedItems(for: section),
            demand: captureDemand()
        )
        guard !items.isEmpty else {
            return CapturePass()
        }
        let revealedSection = appState.menuBarManager.sectionController.revealedSection
        let shouldUseFreshBounds = Self.shouldUseFreshBounds(
            for: section,
            revealedSection: revealedSection
        )
        // A reveal just put these back on the bar, so they get a fresh attempt
        // whatever their record says. The pass only sets the record aside; it is
        // forgotten when the pass commits, so a discarded pass forgives nothing.
        let forgivenTags = section != .visible && shouldUseFreshBounds
            ? Set(items.map(\.tag))
            : []
        let geometryOwners = Self.captureGeometryOwners(
            for: items,
            knownItems: appState.itemManager.managedItems,
            recentItems: appState.itemManager.onScreenItemSnapshot.items
        )
        // A pass the reflow is about to skip takes no picture, so it has nothing to wait for.
        let reflowSkipsPass = Self.skipsPassForReflow(
            reflowing: appState.barSettling.hold(for: .agentNudge) != nil,
            consecutiveSkips: consecutiveReflowSkips
        )
        if !reflowSkipsPass, Self.settlesRevealedPixels(
            for: section,
            revealedSection: revealedSection,
            lastRevealChange: appState.barSettling.lastRevealChange,
            now: .now
        ) {
            await settleRevealedSection(items, appState: appState, reader: LiveMenuBarCaptureReader(geometryOwners: geometryOwners))
        }
        // A stale item cache can let concealed items into this pass; the crop
        // loop rejects them against this set.
        let concealedIdentifiers = appState.menuBarManager.sectionController
            .effectivelyConcealedIdentifiers
        let captureResult = await captureImages(
            of: items,
            scale: scale,
            appState: appState,
            // Re-read geometry before the screenshot, including visible items;
            // the post-capture ownership check still rejects movement or ambiguity.
            freshBounds: shouldUseFreshBounds,
            concealedIdentifiers: concealedIdentifiers,
            forgivenTags: forgivenTags,
            geometryOwners: geometryOwners
        )
        if !captureResult.unreadable.isEmpty {
            MenuBarItemImageCache.diagLog.debug(
                "captureImages: \(captureResult.unreadable.count) items failed capture"
            )
        }
        return captureResult
    }
}
