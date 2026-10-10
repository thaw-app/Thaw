//
//  ClickReactionVerifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

// MARK: - ClickReactionVerifier

/// Watches for evidence that an owner actually *did* something after we
/// clicked one of its menu bar items.
///
/// A wedged app, or one dropping synthetic events, still drains the queue,
/// so a delivered click proves nothing. Only a verified reaction may clear an
/// unresponsive mark, or the item jitters through a retry loop every click.
///
/// ## What counts as a reaction
///
/// - The owner put a new window on screen (menu, popover, panel).
/// - The item's own window changed size or left the screen.
///
/// No reaction is not failure: a mute toggle can flip a glyph at fixed
/// width. An unverified click can't clear a mark, but never earns one.
nonisolated enum ClickReactionVerifier {
    // MARK: Types

    /// What the owner was observed to do.
    enum Reaction: Equatable {
        /// The window is the best candidate for what the click opened.
        case openedInterface(CGWindowID)

        /// The item's own window changed size or left the screen.
        case itemChanged

        /// Not proof of failure.
        case unobserved

        /// Whether the owner was seen doing anything at all.
        var didReact: Bool {
            self != .unobserved
        }

        var openedWindowID: CGWindowID? {
            if case let .openedInterface(windowID) = self {
                return windowID
            }
            return nil
        }
    }

    /// The observable state of the world immediately before a click.
    struct Snapshot {
        /// Owner and source, since helper-hosted items are common.
        let pids: Set<pid_t>

        let itemWindowID: CGWindowID

        let itemBounds: CGRect

        /// So an already-open window isn't mistaken for one the click opened.
        let onScreenWindowIDs: Set<CGWindowID>
    }

    // MARK: Tuning

    /// A real menu opens well inside this; the full wait only happens when
    /// nothing reacts.
    private static let budget = Duration.milliseconds(250)

    private static let pollInterval = Duration.milliseconds(20)

    /// Sub-point differences are window server rounding.
    private static let boundsEpsilon: CGFloat = 1

    // MARK: Observing

    /// Must be called before the click is posted.
    static func snapshot(for item: MenuBarItem) -> Snapshot {
        Snapshot(
            pids: Set([item.ownerPID, item.sourcePID].compactMap(\.self)),
            itemWindowID: item.windowID,
            itemBounds: item.bounds,
            onScreenWindowIDs: Set(Bridging.getWindowList(option: .onScreen))
        )
    }

    /// Call after the click is posted and the cursor restored, so the
    /// caller's own overlay work doesn't pollute the window list.
    static func verify(against snapshot: Snapshot) async -> Reaction {
        let deadline = ContinuousClock.now.advanced(by: budget)
        while true {
            if let reaction = observe(snapshot) {
                return reaction
            }
            guard ContinuousClock.now < deadline else {
                return .unobserved
            }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                // Cancellation says nothing about the owner.
                return .unobserved
            }
        }
    }

    /// One look without waiting, for a caller that already blocked, such as
    /// an AX action that timed out.
    ///
    /// - Returns: `nil` when nothing has been seen yet. Never
    ///   ``Reaction/unobserved``, since it hasn't waited.
    static func reactionSoFar(against snapshot: Snapshot) -> Reaction? {
        observe(snapshot)
    }

    /// Returns `nil` when it's still too early to say.
    private static func observe(_ snapshot: Snapshot) -> Reaction? {
        let newWindowIDs = Bridging.getWindowList(option: .onScreen)
            .filter { !snapshot.onScreenWindowIDs.contains($0) }

        if !newWindowIDs.isEmpty {
            let candidates = WindowInfo.createWindows(from: newWindowIDs)
            if let window = interfaceWindow(among: candidates, ownedBy: snapshot.pids) {
                return .openedInterface(window.windowID)
            }
        }

        if itemChanged(snapshot) {
            return .itemChanged
        }

        return nil
    }

    // MARK: Decisions

    /// Picks the window that best represents what the click opened. Split
    /// out so it's testable without a window server.
    ///
    /// - Parameters:
    ///   - candidates: Windows that were not on screen at snapshot time.
    ///   - pids: The processes whose windows count as a reaction.
    static func interfaceWindow(
        among candidates: [WindowInfo],
        ownedBy pids: Set<pid_t>
    ) -> WindowInfo? {
        let owned = candidates.filter { pids.contains($0.ownerPID) }
        guard !owned.isEmpty else {
            return nil
        }
        // Prefer a menu-level window, but any owned window is a reaction.
        return owned.first(where: \.isMenuRelated) ?? owned.first
    }

    /// Whether an item's own window changed in a way only the owner could
    /// have caused.
    ///
    /// Only size counts; the origin moves whenever the menu bar reflows.
    ///
    /// - Parameters:
    ///   - before: The item's bounds at snapshot time.
    ///   - after: The item's bounds now, or `nil` if its window is gone.
    static func itemChanged(from before: CGRect, to after: CGRect?) -> Bool {
        guard let after else {
            // Gone: removed or replaced, both by the owner.
            return true
        }
        return abs(after.width - before.width) > boundsEpsilon ||
            abs(after.height - before.height) > boundsEpsilon
    }

    private static func itemChanged(_ snapshot: Snapshot) -> Bool {
        guard Bridging.isWindowOnScreen(snapshot.itemWindowID) else {
            // Counts only if it was on screen at snapshot time; a stale ID
            // says nothing about the click.
            return snapshot.onScreenWindowIDs.contains(snapshot.itemWindowID)
        }
        return itemChanged(from: snapshot.itemBounds, to: Bridging.getWindowBounds(for: snapshot.itemWindowID))
    }
}
