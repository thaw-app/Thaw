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

    /// The per-call result of one reanchorRealDisplayAsMain transaction, so the
    /// caller can verify success and log the codes from the field.
    struct ReanchorResult {
        let beginOK: Bool
        let originReal: CGError
        let originPhantom: CGError
        let complete: CGError

        var success: Bool {
            beginOK && complete == .success
        }
    }

    /// Anchors realMain at the global origin (the origin defines the main display)
    /// and parks this phantom immediately to realMain's right, in one display
    /// configuration transaction. Returns the per-call error codes.
    ///
    /// macOS chooses where a freshly added display lands and, on some saved
    /// arrangements (e.g. a machine that has had an external/AirPlay display), it
    /// places the phantom at the origin and makes it the main display a moment
    /// after it comes online; the menu bar and windows then jump onto the tiny
    /// phantom and the screen visibly snaps small until teardown. A single call
    /// right after creation can therefore fire before the phantom has taken main
    /// and do nothing, so the caller re-asserts this in a verify loop for the
    /// phantom's lifetime rather than assuming one call sticks. macOS clamps the
    /// phantom adjacent to the real display regardless of how large an offset is
    /// requested, so the real display's width is used as the offset. realMain must
    /// be captured before the phantom is created, while it is still the only one.
    func reanchorRealDisplayAsMain(_ realMain: CGDirectDisplayID) -> ReanchorResult {
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let configRef else {
            return ReanchorResult(beginOK: false, originReal: .failure, originPhantom: .failure, complete: .failure)
        }
        let originReal = CGConfigureDisplayOrigin(configRef, realMain, 0, 0)
        let offset = Int32(clamping: CGDisplayPixelsWide(realMain))
        let originPhantom = CGConfigureDisplayOrigin(configRef, displayID, offset, 0)
        let complete = CGCompleteDisplayConfiguration(configRef, .forSession)
        return ReanchorResult(beginOK: true, originReal: originReal, originPhantom: originPhantom, complete: complete)
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
