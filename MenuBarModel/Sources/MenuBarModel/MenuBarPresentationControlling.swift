//
//  MenuBarPresentationControlling.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Controls how macOS presents the system menu bar.
///
/// macOS 27's menu bar agent exposes a per-app session, needing no private
/// entitlement, that answers presentation requests the older surfaces cannot:
/// forcing the bar visible (fullscreen spaces included), hiding it globally,
/// and toggling auto-show. These are the active counterparts to watching
/// NSApp.currentSystemPresentationOptions: that observation learns when
/// something else changed the bar's presentation, this seam changes it.
///
/// The state is agent-owned and scoped to the owning process's session. It
/// reverts when the process dies, so nothing here carries a
/// restore-on-termination obligation.
@MainActor
public protocol MenuBarPresentationControlling: AnyObject {
    /// Whether the platform surface exists on this system.
    ///
    /// Calls on an unsupported system are no-ops returning false rather than
    /// crashing, so callers may skip this check for fire-and-forget actions.
    var isSupported: Bool { get }

    /// Forces the system menu bar visible, fullscreen spaces included.
    ///
    /// This drives the system's own reveal state machine, with no synthetic
    /// mouse or keyboard events, so the bar behaves as if the user had revealed it.
    @discardableResult
    func revealSystemMenuBar() async -> Bool

    /// Hides (or restores) the system menu bar in every context.
    ///
    /// The hidden state reverts when the owning process's session dies;
    /// treat the first production use as confirming that revert behavior on
    /// a released operating system.
    @discardableResult
    func setSystemMenuBarHidden(_ hidden: Bool) async -> Bool

    /// Enables or disables auto-show, the hover-at-the-top-edge reveal.
    @discardableResult
    func setSystemMenuBarAutoShowEnabled(_ enabled: Bool) async -> Bool

    // MARK: Per-Space behavior

    /// Hides (or restores) the menu bar in one Space only, leaving other
    /// Spaces untouched. spaceID is the CGS Space identifier.
    @discardableResult
    func setSystemMenuBarHidden(_ hidden: Bool, spaceID: UInt64) async -> Bool

    /// Disables (or re-enables) hover auto-show in one Space only.
    @discardableResult
    func setSystemMenuBarAutoShowDisabled(_ disabled: Bool, spaceID: UInt64) async -> Bool

    /// Sets the auto-hidden reveal-strip height in one Space only, a control
    /// macOS itself does not expose anywhere.
    @discardableResult
    func setSystemMenuBarAutohideHeight(_ height: Double, spaceID: UInt64) async -> Bool

    /// Drops all per-Space menu bar overrides for spaceID, restoring the
    /// system default behavior.
    @discardableResult
    func clearSystemMenuBarOverrides(forSpace spaceID: UInt64) async -> Bool

    /// Makes a user (non-fullscreen) Space's menu bar take the fullscreen
    /// appearance. Accepted by the agent on macOS 27; the visual effect has
    /// not yet been confirmed by eye, so treat the first production use as the
    /// confirmation.
    @discardableResult
    func setFullScreenAppearanceOnUserSpace(_ enabled: Bool) async -> Bool
}
