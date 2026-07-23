//
//  OverflowFallbackIcon.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// MARK: - OverflowFallbackIcon

/// Interim fallback that renders menu bar items using their owning app's icon
/// instead of the live screenshot crop when captured glyphs are unavailable or
/// the user opts out of live previews.
///
/// On macOS 27 native hiding / overflow often produces incomplete hosting-window
/// crops. When the image cache clears those failed captures, this fallback keeps
/// IceBar and the layout editor from showing blank slots until a complete
/// capture succeeds.
enum OverflowFallbackIcon {
    /// The shared Control Center icon, reused for system-owned items whose
    /// `sourceApplication` resolves to a system agent rather than a real app.
    private static let controlCenterIcon: NSImage? = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
        .first?
        .icon

    /// Whether macOS 27 may render app icons when live captures are missing.
    @MainActor
    static func supportsMissingCaptureFallback(for section: MenuBarSection.Name?) -> Bool {
        guard #available(macOS 27, *) else { return false }
        return section != nil
    }

    /// Whether items in `section` should use the app icon instead of a captured
    /// glyph.
    @MainActor
    static func shouldPreferAppIcon(
        for item: MenuBarItem,
        in section: MenuBarSection.Name?,
        appState: AppState,
        cachedImage: NSImage?,
        isNativeOverflowActive: Bool = false
    ) -> Bool {
        guard supportsMissingCaptureFallback(for: section) else { return false }
        // These processes host multiple distinct Apple modules rather than one
        // app-owned status item. Keep their captures, including Siri, instead
        // of substituting the host process's application icon.
        guard !usesCapturedSystemPreview(item) else { return false }
        // While native notch overflow is active, releasing Thaw's assertion
        // does not guarantee that any hidden item becomes a normal first-row
        // glyph. Capturing in that state can read the overflow chevron instead.
        // Ignore even a populated cache entry because it may be that stale
        // arrow crop from an earlier prewarm pass.
        if isNativeOverflowActive {
            return true
        }
        // User escape hatch: always render the owning app's icon instead of the
        // live capture, regardless of whether a (possibly polluted) capture
        // exists. Lets users sidestep macOS 27 native-overflow capture bleed.
        if appState.settings.advanced.alwaysUseAppIconForMenuBarItems {
            // Do not turn a stale cache entry into a generic placeholder after
            // its source app has quit. Without the override, a missing capture
            // renders nothing; preserve that behavior when there is no live app
            // icon to substitute.
            return selectedThawIcon(for: item, appState: appState) != nil || appIcon(for: item) != nil
        }
        return cachedImage == nil
    }

    /// The image Thaw Bar / layout UI should display for a concealed item.
    @MainActor
    static func resolvedImage(
        for item: MenuBarItem,
        section: MenuBarSection.Name?,
        appState: AppState,
        cachedImage: NSImage?,
        visibleControlItemState: ControlItem.HidingState? = nil,
        isNativeOverflowActive: Bool = false
    ) -> NSImage? {
        if shouldPreferAppIcon(
            for: item,
            in: section,
            appState: appState,
            cachedImage: cachedImage,
            isNativeOverflowActive: isNativeOverflowActive
        ) {
            return preferredImage(
                for: item,
                appState: appState,
                visibleControlItemState: visibleControlItemState
            )
        }
        return cachedImage
    }

    /// The image used when app-icon presentation is active. Thaw's visible
    /// control item uses the icon selected in General settings; other items use
    /// their owning application's icon.
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
        ) ?? image(for: item)
    }

    /// Thaw's selected status-item icon for the current visible-section state.
    @MainActor
    static func selectedThawIcon(
        for item: MenuBarItem,
        appState: AppState,
        visibleControlItemState: ControlItem.HidingState? = nil
    ) -> NSImage? {
        guard item.tag.matchesVisibleControlItem else { return nil }

        let icon = appState.settings.general.iceIcon
        let state = visibleControlItemState
            ?? appState.menuBarManager.section(withName: .visible)?.controlItem.state
            ?? .hideSection
        return switch state {
        case .showSection: icon.visible.nsImage(for: appState)
        case .hideSection: icon.hidden.nsImage(for: appState)
        }
    }

    /// The owning app's icon for `item`, falling back to a generic menu-bar
    /// glyph when no application can be resolved (e.g. some system items).
    static func image(for item: MenuBarItem) -> NSImage? {
        appIcon(for: item) ?? NSImage(
            systemSymbolName: "menubar.rectangle",
            accessibilityDescription: item.displayName
        )
    }

    /// The actual icon available for the item's currently live source app.
    /// Unlike `image(for:)`, this deliberately has no generic fallback so the
    /// app-icon override can distinguish a quit app from a live one.
    private static func appIcon(for item: MenuBarItem) -> NSImage? {
        switch item.tag.namespace {
        case .menuBarAgent:
            return nil
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return controlCenterIcon
        default:
            return item.sourceApplication?.icon
        }
    }

    /// Whether an Apple hosting process should keep its captured preview.
    static func usesCapturedSystemPreview(_ item: MenuBarItem) -> Bool {
        switch item.tag.namespace {
        case .menuBarAgent, .controlCenter, .systemUIServer:
            true
        default:
            false
        }
    }
}
