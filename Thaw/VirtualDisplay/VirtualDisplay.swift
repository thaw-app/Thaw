//
//  VirtualDisplay.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// A headless virtual display created via the private CGVirtualDisplay API.
///
/// On macOS 26 the bundle-ID "marker" windows that source-PID marker-pair
/// resolution relies on are only published by the window server when two or
/// more displays exist. On a single physical display they are absent, so
/// Control-Center-hosted widgets (Little Snitch's agent, Timemator, etc.) stay
/// unresolved. Briefly adding a virtual display makes the window server publish
/// those markers so the existing marker-pair pass can resolve the orphans; the
/// resolved windowID -> PID mappings persist in the cache after the display is
/// removed, so it only needs to be present long enough to resolve once.
final class VirtualDisplay {
    private let handle: UnsafeMutableRawPointer
    private var isValid = true

    /// The display identifier assigned by the window server. Always non-zero;
    /// create returns nil when no valid identifier is available.
    let displayID: CGDirectDisplayID

    private init(handle: UnsafeMutableRawPointer, displayID: CGDirectDisplayID) {
        self.handle = handle
        self.displayID = displayID
    }

    /// Whether the private CGVirtualDisplay class is present at runtime. When
    /// false, creation would fail, so callers can skip the attempt entirely.
    static var isSupported: Bool {
        NSClassFromString("CGVirtualDisplay") != nil
    }

    /// Creates a virtual display, or returns nil when the private API is
    /// unavailable or creation fails (the shim resolves the classes at runtime
    /// and catches Objective-C exceptions, so this never crashes).
    static func create() -> VirtualDisplay? {
        guard let handle = ThawVirtualDisplayCreate() else {
            return nil
        }
        let displayID = ThawVirtualDisplayGetID(handle)
        guard displayID != 0 else {
            // Without a valid display ID the phantom cannot be excluded from
            // display enumeration (Bridging.excludedDisplayID would only filter
            // the null display), so it would leak into per-display behaviours.
            // Treat it as a creation failure and tear the handle down.
            ThawVirtualDisplayDestroy(handle)
            return nil
        }
        return VirtualDisplay(handle: handle, displayID: displayID)
    }

    /// Keeps the real display the system main display and parks this phantom to
    /// its right, so adding the phantom never relocates the menu bar or reshuffles
    /// the user's windows. macOS places a freshly added display at the global
    /// origin in some arrangements, which makes it the main display (the main
    /// display is whichever sits at the origin); when that happens the menu bar
    /// and windows jump onto the tiny phantom and the screen visibly snaps small
    /// until teardown. Re-anchoring the real display at the origin and offsetting
    /// the phantom undoes that. realMain must be captured before the phantom is
    /// created, while the real display is still the only one.
    func excludeFromMainDisplay(realMain: CGDirectDisplayID) {
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let configRef else {
            return
        }
        // The main display is the one at the global origin, so anchoring the real
        // display there guarantees it stays main regardless of where the window
        // server initially placed the phantom.
        CGConfigureDisplayOrigin(configRef, realMain, 0, 0)
        // Place the phantom immediately to the right of the real display so it is
        // never at the origin and never overlaps the real desktop.
        let offset = Int32(clamping: CGDisplayPixelsWide(realMain))
        CGConfigureDisplayOrigin(configRef, displayID, offset, 0)
        if CGCompleteDisplayConfiguration(configRef, .forSession) != .success {
            CGCancelDisplayConfiguration(configRef)
        }
    }

    /// Removes the virtual display. Idempotent.
    func invalidate() {
        guard isValid else {
            return
        }
        isValid = false
        ThawVirtualDisplayDestroy(handle)
    }

    deinit {
        if isValid {
            ThawVirtualDisplayDestroy(handle)
        }
    }
}
