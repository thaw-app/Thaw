//
//  OverflowFallbackIcon.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import SwiftUI

// MARK: - MenuBarItemDisplayImage

/// Keep engine captures CoreGraphics-only; the view layer can substitute NSImage app icons.
enum MenuBarItemDisplayImage {
    case capture(MenuBarItemGlyphCapture)
    case appIcon(NSImage)

    /// Intrinsic point size: capture pixels divided by scale, or the AppKit image size.
    var pointSize: CGSize {
        switch self {
        case let .capture(capture): capture.pointSize
        case let .appIcon(image): image.size
        }
    }

    /// App icons may be template images; pixel captures never are.
    var isTemplate: Bool {
        switch self {
        case .capture: false
        case let .appIcon(image): image.isTemplate
        }
    }

    /// Template icons and single-ink transparent captures can use another surface's ink.
    @MainActor
    var isReinkable: Bool {
        switch self {
        case let .capture(capture): capture.isSingleInkGlyph
        case let .appIcon(image): image.isTemplate
        }
    }

    var swiftUIImage: Image {
        switch self {
        case let .capture(capture): Image(decorative: capture.cgImage, scale: capture.scale)
        case let .appIcon(image): Image(nsImage: image)
        }
    }

    /// Fit downward only; upscaling native raster glyphs blurs them in taller rows.
    /// Nil or non-positive row/image heights leave intrinsic size unchanged.
    func targetSize(fittingHeight rowHeight: CGFloat?) -> CGSize {
        let intrinsic = pointSize
        guard intrinsic.height > 0, let rowHeight, rowHeight > 0 else {
            return intrinsic
        }
        let scale = min(1, rowHeight / intrinsic.height)
        return CGSize(width: intrinsic.width * scale, height: intrinsic.height * scale)
    }
}

// MARK: - MenuBarItemGlyph

/// Share fitted sizing, source templating, and high-quality raster downscaling across bar and overlay cells.
/// Hover and click treatments stay with each cell.
struct MenuBarItemGlyph: View {
    let image: MenuBarItemDisplayImage

    /// Nil draws at intrinsic size; otherwise fit to the row height.
    let fittingHeight: CGFloat?

    /// Reink single-ink captures on the Thaw Bar, whose background may have opposite brightness.
    /// Keep original ink over the menu bar, where it already matches.
    var reinksCaptures = false

    var body: some View {
        let size = image.targetSize(fittingHeight: fittingHeight)
        // Templating opaque app icons makes blank blocks; preserve their colors.
        image.swiftUIImage
            .renderingMode(image.isTemplate || (reinksCaptures && image.isReinkable) ? .template : .original)
            .interpolation(.high)
            .antialiased(true)
            .resizable()
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - OverflowFallbackIcon

/// App icons keep slots usable when hiding or overflow causes incomplete crops, or users disable live previews.
enum OverflowFallbackIcon {
    /// Cache by PID: NSRunningApplication and icon lookup allocate fresh objects on every view evaluation.
    /// Repeated body reads can allocate faster than autorelease pools drain.
    @MainActor
    private static var appIconsByPID: [pid_t: NSImage?] = [:]

    /// Remove quit-process entries to bound cache growth and reread icons after relaunch.
    @MainActor
    static func forgetIcon(forPID pid: pid_t) {
        appIconsByPID.removeValue(forKey: pid)
    }

    /// Use this cache instead of sourceApplication?.icon to avoid allocations on every body evaluation.
    @MainActor
    static func cachedAppIcon(forPID pid: pid_t) -> NSImage? {
        if let cached = appIconsByPID[pid] {
            return cached
        }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        appIconsByPID[pid] = icon
        return icon
    }

    /// App-icon fallback requires a known section.
    @MainActor
    static func supportsMissingCaptureFallback(for section: MenuBarSection.Name?) -> Bool {
        return section != nil
    }

    @MainActor
    static func shouldPreferAppIcon(
        for item: MenuBarItem,
        in section: MenuBarSection.Name?,
        appState: AppState,
        hasUsableCapture: Bool
    ) -> Bool {
        guard supportsMissingCaptureFallback(for: section) else { return false }
        // Apple hosts contain distinct modules, including Siri; their process icon cannot replace each glyph.
        guard !usesCapturedSystemPreview(item) else { return false }
        // Nothing on the bar to capture, and a reveal would flash it there.
        if appState.itemManager.isThawBarOnly(item) {
            return appIcon(for: item) != nil || image(for: item) != nil
        }
        // Native overflow needs no case: captures that meet its chevron are refused, and concealed
        // items are not revealed for one on an overflowed bar.
        // The app-icon override lets users avoid native-overflow capture bleed even with populated captures.
        if appState.settings.alwaysUseAppIconForMenuBarItems {
            // Without a live app icon, preserve missing-capture behavior rather than replacing a quit app with a placeholder.
            return selectedThawIcon(for: item, appState: appState) != nil || appIcon(for: item) != nil
        }
        return !hasUsableCapture
    }

    /// Wider captures are likely bar/chrome crops unless the item itself is that wide.
    static let maximumUsableCaptureWidth: CGFloat = 240

    /// No single item is wider than this, whatever its bounds say.
    static let maximumItemWidth: CGFloat = 720

    /// Share capture validation across surfaces; wide multi-module items raise the limit to their own width.
    static func isUsableCapture(width: CGFloat?, itemWidth: CGFloat? = nil) -> Bool {
        guard let width else { return false }
        let itemLimit = itemWidth.map { min($0 + 8, maximumItemWidth) } ?? 0
        return width <= max(maximumUsableCaptureWidth, itemLimit)
    }

    /// Fully transparent crops pass the width test but would draw empty cells.
    static func isUsableCapture(_ capture: MenuBarItemGlyphCapture?, for item: MenuBarItem? = nil) -> Bool {
        guard let capture,
              isUsableCapture(width: capture.pointSize.width, itemWidth: item?.bounds.width)
        else { return false }
        return !capture.isEffectivelyBlank
    }

    /// The image Thaw Bar / layout UI should display for a concealed item.
    @MainActor
    static func resolvedImage(
        for item: MenuBarItem,
        section: MenuBarSection.Name?,
        appState: AppState,
        capturedImage: MenuBarItemGlyphCapture?,
        visibleControlItemState: ControlItem.HidingState? = nil
    ) -> MenuBarItemDisplayImage? {
        if shouldPreferAppIcon(
            for: item,
            in: section,
            appState: appState,
            hasUsableCapture: isUsableCapture(capturedImage, for: item)
        ) {
            return preferredImage(
                for: item,
                appState: appState,
                visibleControlItemState: visibleControlItemState
            ).map { .appIcon($0) }
        }
        if let capturedImage, isUsableCapture(capturedImage, for: item) {
            return .capture(capturedImage)
        }
        // Substitute a glyph when both capture and app icon are missing to avoid a blank tile.
        return preferredImage(
            for: item,
            appState: appState,
            visibleControlItemState: visibleControlItemState
        ).map { .appIcon($0) }
    }

    /// Share one image pass between layout measurement and rendering.
    /// section lets single-section bars return a constant and mixed-section overlays look up each item.
    @MainActor
    static func resolvedImages(
        for items: [MenuBarItem],
        appState: AppState,
        imageCache: MenuBarItemImageCache,
        visibleControlItemState: ControlItem.HidingState? = nil,
        section: (MenuBarItem) -> MenuBarSection.Name?
    ) -> [MenuBarItemTag: MenuBarItemDisplayImage] {
        items.reduce(into: [MenuBarItemTag: MenuBarItemDisplayImage]()) { result, item in
            result[item.tag] = resolvedImage(
                for: item,
                section: section(item),
                appState: appState,
                capturedImage: imageCache.image(for: item.tag),
                visibleControlItemState: visibleControlItemState
            )
        }
    }

    /// Prefer Thaw's selected control icon, user choices, bundled Thaw Bar Only glyphs, then app icons.
    @MainActor
    static func preferredImage(
        for item: MenuBarItem,
        appState: AppState,
        visibleControlItemState: ControlItem.HidingState? = nil
    ) -> NSImage? {
        selectedThawIcon(
            for: item,
            appState: appState,
            visibleControlItemState: visibleControlItemState
        ) ?? MenuBarItemIconChoices.shared.image(for: item)
            ?? thawBarOnlyIcon(for: item, appState: appState)
            ?? image(for: item)
    }

    /// Uncaptured Thaw Bar Only items prefer bundled status glyphs over app icons.
    @MainActor
    private static func thawBarOnlyIcon(for item: MenuBarItem, appState: AppState) -> NSImage? {
        guard appState.itemManager.isThawBarOnly(item), let pid = item.sourcePID else { return nil }
        return BundledStatusIcon.image(forBundleAt: NSRunningApplication(processIdentifier: pid)?.bundleURL)
    }

    /// Thaw's selected status-item icon for the current visible-section state.
    @MainActor
    static func selectedThawIcon(
        for item: MenuBarItem,
        appState: AppState,
        visibleControlItemState: ControlItem.HidingState? = nil
    ) -> NSImage? {
        guard item.tag.matchesVisibleControlItem else { return nil }

        let icon = appState.settings.thawIcon
        let state = visibleControlItemState
            ?? appState.menuBarManager.section(withName: .visible)?.controlItem.state
            ?? .hideSection
        return switch state {
        case .showSection: icon.visible.nsImage(for: appState)
        case .hideSection: icon.hidden.nsImage(for: appState)
        }
    }

    /// Fall back to a generic glyph when the app is unresolved.
    /// MenuBarItemDisplayName avoids allocating process wrappers for accessibility text on every body read.
    @MainActor
    static func image(for item: MenuBarItem) -> NSImage? {
        appIcon(for: item) ?? NSImage(
            systemSymbolName: "menubar.rectangle",
            accessibilityDescription: MenuBarItemDisplayName.displayName(for: item)
        )
    }

    /// No generic fallback, so app-icon overrides can distinguish quit apps from live ones.
    @MainActor
    private static func appIcon(for item: MenuBarItem) -> NSImage? {
        switch item.tag.namespace {
        case .menuBarAgent:
            return nil
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return ControlCenterIcon.image
        default:
            // Stand-in bundles have no app icon; use their identifying glyph.
            if let glyph = ThawExtraGlyph.image(for: item) {
                return glyph
            }
            guard let sourcePID = item.sourcePID else {
                return nil
            }
            return cachedAppIcon(forPID: sourcePID)
        }
    }

    /// Off-main-actor capture checks must agree with shouldPreferAppIcon so skipped captures are not needed by rendering.
    static nonisolated func canRenderAppIconWithoutCapture(for item: MenuBarItem) -> Bool {
        switch item.tag.namespace {
        case .menuBarAgent, .controlCenter, .systemUIServer:
            // Their captures are kept by usesCapturedSystemPreview.
            return false
        case .textInputMenuAgent:
            // Presented with the Control Center icon, or the generic glyph.
            return true
        default:
            // Unresolved source processes cannot supply app icons and need captures.
            return item.sourcePID != nil
        }
    }

    /// Share the system-preview rule with off-main-actor capture passes so rendering never expects a skipped capture.
    static nonisolated func usesCapturedSystemPreview(_ item: MenuBarItem) -> Bool {
        switch item.tag.namespace {
        case .menuBarAgent, .controlCenter, .systemUIServer:
            true
        default:
            false
        }
    }
}
