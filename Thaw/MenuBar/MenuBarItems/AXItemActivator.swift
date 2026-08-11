//
//  AXItemActivator.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa

/// Activates a menu bar item by invoking an accessibility action (AXShowMenu,
/// falling back to AXPress) on its resolved AX element, instead of
/// synthesizing mouse events. This avoids leaking synthetic events into
/// system gesture handling and lets items with their own click handling
/// (e.g. the Wi-Fi picker) behave exactly as they would for a real click.
///
/// Controlled by `AdvancedSettings.useAXClickDelivery` (default on; no
/// longer surfaced in Settings). On any failure the caller
/// (`MenuBarItemManager.click(item:with:)`) falls back to the existing
/// synthetic click path unchanged.
@MainActor
enum AXItemActivator {
    enum ActivationError: Error {
        /// The item's AX element could not be resolved via hit-testing or
        /// via the owning app's extras menu bar.
        case elementNotFound
        /// The resolved element's AX frame does not line up with the item's
        /// window bounds (within tolerance), so acting on it would risk
        /// hitting the wrong item.
        case frameMismatch
        /// Both AXShowMenu and AXPress failed on the verified element.
        case actionFailed
    }

    /// Tolerance (in points) used when verifying that a candidate element's
    /// AX frame corresponds to the target item's window bounds. Mirrors the
    /// tolerance `pressItemViaAccessibility` uses for its own child-frame
    /// matching.
    private static let frameMatchTolerance: CGFloat = 10

    /// Messaging timeout applied to AX handles created here, so a
    /// non-responsive app can't block a click indefinitely.
    private static let messagingTimeout: Float = 0.25

    /// Activates `item` via an accessibility action.
    ///
    /// - Throws: ``ActivationError`` when the item's AX element can't be
    ///   resolved and verified, or when neither AXShowMenu nor AXPress had any
    ///   effect — an action the element refused *and* no sign of the owner
    ///   reacting. Callers should fall back to the synthetic click path on any
    ///   error; ``ActivationError/actionFailed`` in particular now means the
    ///   item was left alone, so clicking it is safe.
    static func activate(item: MenuBarItem) async throws {
        guard let element = resolveElement(for: item) else {
            throw ActivationError.elementNotFound
        }

        try? element.setMessagingTimeout(messagingTimeout)

        guard let elementFrame = AXHelpers.frame(for: element) else {
            throw ActivationError.frameMismatch
        }

        guard Self.framesMatch(elementFrame, item.bounds, tolerance: frameMatchTolerance) else {
            throw ActivationError.frameMismatch
        }

        let snapshot = ClickReactionVerifier.snapshot(for: item)
        let worked = Self.performFirstEffectiveAction(
            [.showMenu, .press],
            perform: { (try? element.performAction($0)) != nil },
            didReact: { ClickReactionVerifier.reactionSoFar(against: snapshot)?.didReact == true }
        )
        guard worked else {
            throw ActivationError.actionFailed
        }
    }

    /// Performs `actions` in order, stopping at the first one that has an
    /// effect.
    ///
    /// An action has an effect when the element accepts it **or** when the item
    /// is observed reacting to it. The second half is the whole point. A
    /// thrown action is not a no-op: `AXShowMenu` on a status item opens the
    /// menu and then blocks, because the menu runs a modal tracking loop and
    /// the app cannot answer the accessibility message while it does, so
    /// ``messagingTimeout`` expires on precisely the calls that worked.
    ///
    /// Reading that as failure escalates, and every escalation from here is a
    /// second activation of an item whose menu is already open: `AXPress`
    /// toggles it shut, and the synthetic click the caller falls back to after
    /// that toggles it again. The user sees the menu they asked for appear and
    /// vanish within the same second, which is what happens for third-party
    /// items whose menus block the reply (#924).
    ///
    /// Generic over the action so the rule can be exercised without an
    /// accessibility server.
    static nonisolated func performFirstEffectiveAction<A>(
        _ actions: [A],
        perform: (A) -> Bool,
        didReact: () -> Bool
    ) -> Bool {
        for action in actions {
            if perform(action) {
                return true
            }
            if didReact() {
                return true
            }
        }
        return false
    }

    /// Resolves the AX element for `item`.
    ///
    /// Resolution order:
    /// 1. Hit-test the systemwide element at the item's on-screen center
    ///    (same coordinate space `HIDEventManager` uses for its own AX
    ///    hit-testing: CoreGraphics global, top-left origin — the same space
    ///    as `MenuBarItem.bounds`, so no conversion is needed).
    /// 2. Fall back to the owning app's extras menu bar, matching the child
    ///    whose AX frame contains the item's center.
    private static func resolveElement(for item: MenuBarItem) -> UIElement? {
        let center = item.bounds.center

        try? systemWideElement.setMessagingTimeout(messagingTimeout)
        if let hit = AXHelpers.element(at: center) {
            try? hit.setMessagingTimeout(messagingTimeout)
            return hit
        }

        // Fall back to sourcePID/ownerPID so this works even when
        // sourcePID hasn't resolved yet, matching the convention used by
        // `MenuBarItemManager.pressItemViaAccessibility`.
        let pid = item.sourcePID ?? item.ownerPID
        guard
            let runningApp = NSRunningApplication(processIdentifier: pid),
            let app = AXHelpers.application(for: runningApp)
        else {
            return nil
        }
        try? app.setMessagingTimeout(messagingTimeout)

        guard let extrasMenuBar = AXHelpers.extrasMenuBar(for: app) else {
            return nil
        }

        let children = AXHelpers.children(for: extrasMenuBar)
        let frames = children.map { AXHelpers.frame(for: $0) ?? .null }
        guard let index = Self.candidateIndex(inFrames: frames, containing: center) else {
            return nil
        }
        return children[index]
    }

    /// Pure candidate-selection helper: given candidate frames (parallel to
    /// an AX children array) and a target point, returns the index of the
    /// first frame containing the point, or `nil` when none does.
    static nonisolated func candidateIndex(inFrames frames: [CGRect], containing point: CGPoint) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Pure frame-verification helper: whether `candidate`, expanded by
    /// `tolerance` points in every direction, intersects `target`.
    static nonisolated func framesMatch(_ candidate: CGRect, _ target: CGRect, tolerance: CGFloat) -> Bool {
        candidate.insetBy(dx: -tolerance, dy: -tolerance).intersects(target)
    }
}
