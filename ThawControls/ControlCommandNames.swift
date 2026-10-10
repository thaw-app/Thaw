//
//  ControlCommandNames.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// Keep names in sync with Thaw/App/ControlCommandObserver.swift; Darwin mismatches fail silently without delivery receipts.
// Duplication avoids linking Shared/ AppKit helpers into the sandboxed extension; notifications wake the app, while group defaults only carry state.

import Foundation

/// Darwin notification names understood by the running Thaw app.
enum ControlCommandNames {
    /// Show or hide the hidden section of the menu bar.
    /// Mirrors HotkeyAction.toggleHiddenSection.
    static nonisolated let toggleHidden = "com.stonerl.Thaw.control.toggle-hidden"

    /// Enter or leave Zen Mode.
    /// Mirrors HotkeyAction.toggleZenMode.
    static nonisolated let toggleZen = "com.stonerl.Thaw.control.toggle-zen"
}

// Keep suite, key and JSON names in sync with Thaw/App/ControlStatePublisher.swift; mismatches silently render toggles off.

/// Read-only app-published state; the extension cannot compute these values and must not write optimistic guesses.
/// Positive toggle values avoid exposing Thaw's internal section model.
nonisolated struct ControlStateSnapshot: Codable, Sendable {
    /// Whether the hidden section is currently revealed.
    var isHiddenSectionRevealed: Bool
    /// Whether Zen Mode is engaged.
    var isZenModeActive: Bool

    /// Explicit short keys, so a property rename on either side cannot
    /// silently change the on-disk shape.
    enum CodingKeys: String, CodingKey {
        case isHiddenSectionRevealed = "hiddenRevealed"
        case isZenModeActive = "zenActive"
    }

    /// A team-prefixed macOS application group avoids the consent prompt required by group.-prefixed containers.
    static nonisolated let suiteName = "A7CKWF99ML.com.stonerl.Thaw"

    /// Store one JSON blob because UserDefaults has no cross-key transaction; separate Bool writes could expose impossible state.
    static nonisolated let stateKey = "com.stonerl.Thaw.control-state"

    /// Controls cannot draw unknown; use off when no snapshot exists, including after Thaw clears it on clean exit.
    static nonisolated let unavailable = ControlStateSnapshot(
        isHiddenSectionRevealed: false,
        isZenModeActive: false
    )

    /// Missing entitlements, absent data and incompatible schemas all fall back to off.
    /// Accept stale crash/force-quit snapshots: the next toggle, app publication and reload correct them.
    static nonisolated func current() -> ControlStateSnapshot {
        guard
            let defaults = UserDefaults(suiteName: suiteName),
            let data = defaults.data(forKey: stateKey),
            let snapshot = try? JSONDecoder().decode(ControlStateSnapshot.self, from: data)
        else {
            return unavailable
        }
        return snapshot
    }
}
