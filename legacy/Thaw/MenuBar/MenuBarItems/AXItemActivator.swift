//
//  AXItemActivator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AXSwift6
import Cocoa

/// Activates a menu bar item with AXPress instead of synthetic mouse events,
/// which leak into system gesture handling and trip items like the Wi-Fi
/// picker.
///
/// Controlled by AdvancedSettings.useAXClickDelivery (hidden, default on).
/// On failure the caller falls back to the synthetic click.
@MainActor
enum AXItemActivator {
    enum ActivationError: Error {
        case elementNotFound
        /// The AX frame doesn't line up with the window bounds, so it may be
        /// the wrong item.
        case frameMismatch
        case actionFailed
    }

    /// Matches pressItemViaAccessibility's tolerance.
    private static let frameMatchTolerance: CGFloat = 10

    /// So a non-responsive app can't block a click.
    private static let messagingTimeout: Float = 0.25

    /// - Throws: ActivationError when the element can't be resolved and
    ///   verified, or AXPress had no effect. Fall back to a synthetic click;
    ///   after `actionFailed` the item was left alone, so that's safe.
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
            leftClickActions,
            perform: { (try? element.performAction($0)) != nil },
            didReact: { ClickReactionVerifier.reactionSoFar(against: snapshot)?.didReact == true }
        )
        guard worked else {
            throw ActivationError.actionFailed
        }
    }

    /// Accessibility actions that preserve ordinary left-click semantics.
    ///
    /// Not AXShowMenu: Apple status items treat it as a right click.
    static nonisolated let leftClickActions: [Action] = [.press]

    /// Performs actions in order, stopping at the first one that has an
    /// effect.
    ///
    /// An observed reaction also counts: an action that opens a modal menu
    /// can time out while working. Treating that as failure re-activates the
    /// item and the menu flashes shut (#924).
    ///
    /// Generic so it can be tested without an accessibility server.
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

    /// Hit-tests the item's center (same space as MenuBarItem.bounds), then
    /// falls back to the owning app's extras menu bar child containing it.
    private static func resolveElement(for item: MenuBarItem) -> UIElement? {
        let center = item.bounds.center

        try? systemWideElement.setMessagingTimeout(messagingTimeout)
        if let hit = AXHelpers.element(at: center) {
            try? hit.setMessagingTimeout(messagingTimeout)
            return hit
        }

        // sourcePID may not have resolved yet.
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

    /// Index of the first frame containing `point`.
    static nonisolated func candidateIndex(inFrames frames: [CGRect], containing point: CGPoint) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    static nonisolated func framesMatch(_ candidate: CGRect, _ target: CGRect, tolerance: CGFloat) -> Bool {
        candidate.insetBy(dx: -tolerance, dy: -tolerance).intersects(target)
    }
}
