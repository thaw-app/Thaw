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
/// Capturing a menu bar item needs Screen Recording. Without it the Thaw Bar
/// previously rendered nothing at all — the permission was labelled optional,
/// but a user who declined it and then hit notch overflow, which forces the
/// Thaw Bar on by default, had no way to reach their hidden items. An app
/// icon is not as good as the real glyph, and it cannot show a badge or a
/// live value, but it identifies the item well enough to click the right one.
///
/// Ported from `OverflowFallbackIcon` in thaw-next, including the per-process
/// cache, which is load-bearing rather than an optimisation — see
/// ``appIconsByPID``.
enum MenuBarItemIconFallback {
    /// The Control Center icon, shared by every system-hosted item.
    ///
    /// Resolved once: these items are hosted by one process, so reading a
    /// per-item icon would hand back the same image repeatedly.
    private static let controlCenterIcon: NSImage? = NSRunningApplication
        .runningApplications(withBundleIdentifier: SharedConstants.menuBarHostingBundleID)
        .first?
        .icon

    /// Application icons already resolved this session, keyed by owning
    /// process.
    ///
    /// Both halves of resolving one allocate: `NSRunningApplication(processIdentifier:)`
    /// returns a fresh object rather than a shared instance, and `.icon`
    /// builds a new `NSImage` with its own representations. This is read from
    /// SwiftUI view bodies, which re-evaluate whenever anything they observe
    /// changes — with the bar open that is continuous, and resolving per
    /// evaluation allocates faster than the autorelease pool drains, growing
    /// the process for as long as the bar stays up.
    ///
    /// `NSImage?` rather than `NSImage` so a process that has no icon is
    /// remembered as such instead of being re-resolved on every read.
    @MainActor
    private static var appIconsByPID: [pid_t: NSImage?] = [:]

    /// Forgets the cached icon for a process.
    ///
    /// Keeps a relaunched app from being answered out of a dead process's
    /// entry, and stops the map growing across a long session.
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
    /// Callers rendering item icons should come through here rather than
    /// reading `sourceApplication?.icon` directly — see the note on
    /// ``appIconsByPID`` for what that costs inside a view body.
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
    /// Two reasons lead here: there is no capture to draw, or the user asked
    /// for icons regardless. The preference deliberately loses to a missing
    /// icon — an item whose app has quit still renders its stale capture
    /// rather than degrading to a generic glyph, because the capture at
    /// least shows what the item looked like.
    ///
    /// - Parameters:
    ///   - item: The item being rendered.
    ///   - hasCapture: Whether a captured glyph is available for it.
    ///   - prefersAppIcon: The user's `alwaysUseAppIconForMenuBarItems`
    ///     setting. Passed in rather than read from `Defaults` here so that
    ///     SwiftUI views observing `AdvancedSettings` re-render when it is
    ///     toggled.
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
    /// Always answers with something: an item nobody can identify is still
    /// better rendered as a generic glyph than as a gap the user cannot
    /// click.
    @MainActor
    static func image(for item: MenuBarItem) -> NSImage? {
        appIcon(for: item) ?? NSImage(
            systemSymbolName: "menubar.rectangle",
            accessibilityDescription: item.displayName
        )
    }

    /// The icon of the item's live source application.
    ///
    /// Deliberately has no generic fallback, so callers can tell an item
    /// whose app has quit from one that simply has no icon.
    @MainActor
    static func appIcon(for item: MenuBarItem) -> NSImage? {
        switch item.tag.namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            // One process hosts many unrelated modules. Its own icon is the
            // most honest answer available; the item's name carries the rest.
            return controlCenterIcon
        default:
            guard let sourcePID = item.sourcePID else {
                return nil
            }
            return cachedAppIcon(forPID: sourcePID)
        }
    }
}
