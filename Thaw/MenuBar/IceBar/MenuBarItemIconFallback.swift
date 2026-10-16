//
//  MenuBarItemIconFallback.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

/// The owning application's icon, shown where a captured glyph is not
/// available.
///
/// Captures need Screen Recording, which is optional, and notch overflow can
/// force the Thaw Bar on. An app icon is enough to click the right item.
///
/// The per-process cache is load-bearing; see ``appIconsByPID``.
enum MenuBarItemIconFallback {
    /// The Control Center icon once it has been resolved.
    @MainActor
    private static var cachedControlCenterIcon: NSImage?

    /// The Control Center icon, shared by every system-hosted item.
    ///
    /// A miss is not cached: the host may not be running yet, and a cached
    /// `nil` would pin every system item to the generic glyph.
    @MainActor
    private static var controlCenterIcon: NSImage? {
        if let cachedControlCenterIcon {
            return cachedControlCenterIcon
        }
        let icon = NSRunningApplication
            .runningApplications(withBundleIdentifier: SharedConstants.menuBarHostingBundleID)
            .first?
            .icon
        cachedControlCenterIcon = icon
        return icon
    }

    /// Application icons already resolved this session, keyed by owning
    /// process.
    ///
    /// Resolving allocates a new `NSRunningApplication` and `NSImage` each
    /// time. View bodies read this continuously while the bar is open, which
    /// outpaces the autorelease pool and grows memory.
    ///
    /// Optional so a process with no icon is remembered as such.
    @MainActor
    private static var appIconsByPID: [pid_t: NSImage?] = [:]

    /// Forgets the cached icon for a process, so the map doesn't grow across
    /// a long session.
    @MainActor
    static func forgetIcon(forPID pid: pid_t) {
        appIconsByPID.removeValue(forKey: pid)
    }

    /// Drops cached icons for processes that are no longer running.
    @MainActor
    static func forgetIconsForExitedApplications() {
        let live = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        appIconsByPID = appIconsByPID.filter { live.contains($0.key) }
    }

    /// The owning application's icon, resolved once per process.
    ///
    /// Use this instead of `sourceApplication?.icon`; see ``appIconsByPID``.
    @MainActor
    static func cachedAppIcon(forPID pid: pid_t) -> NSImage? {
        if let cached = appIconsByPID[pid] {
            return cached
        }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        appIconsByPID[pid] = icon
        return icon
    }

    /// Whether an item should be drawn as an app icon rather than a capture.
    ///
    /// The preference loses to a missing icon: an item whose app quit keeps
    /// its stale capture rather than a generic glyph.
    ///
    /// - Parameters:
    ///   - item: The item being rendered.
    ///   - hasCapture: Whether a captured glyph is available for it.
    ///   - prefersAppIcon: `alwaysUseAppIconForMenuBarItems`. Passed in so
    ///     observing views re-render when it is toggled.
    @MainActor
    static func shouldUseAppIcon(
        for item: MenuBarItem,
        hasCapture: Bool,
        prefersAppIcon: Bool
    ) -> Bool {
        guard hasCapture else { return true }
        guard prefersAppIcon else { return false }
        return appIcon(for: item) != nil
    }

    /// The image to display for an item that has no usable capture.
    ///
    /// Never nil: a generic glyph beats a gap the user can't click.
    @MainActor
    static func image(for item: MenuBarItem) -> NSImage? {
        appIcon(for: item) ?? NSImage(
            systemSymbolName: "menubar.rectangle",
            accessibilityDescription: item.displayName
        )
    }

    /// The icon of the item's live source application.
    ///
    /// No generic fallback, so callers can tell a quit app from one with no
    /// icon.
    @MainActor
    static func appIcon(for item: MenuBarItem) -> NSImage? {
        switch item.tag.namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            // One process hosts many unrelated modules.
            return controlCenterIcon
        default:
            guard let sourcePID = item.sourcePID else {
                return nil
            }
            return cachedAppIcon(forPID: sourcePID)
        }
    }
}
