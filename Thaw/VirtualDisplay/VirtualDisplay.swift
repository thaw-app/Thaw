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
