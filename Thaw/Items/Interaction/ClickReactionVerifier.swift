//
//  ClickReactionVerifier.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel

// MARK: - ClickReactionVerifier

/// Watches for evidence that an owner actually did something after we
/// clicked one of its menu bar items.
///
/// A delivered post proves nothing: a wedged app still drains the queue. Only
/// a verified reaction may clear an unresponsive mark, or a dead owner is
/// re-forgiven on every click and reruns the full retry loop.
///
/// Evidence is a new owner window (menu, popover, panel) or the item's own
/// window resizing or vanishing. No evidence is not failure (a mute toggle
/// flips a glyph invisibly), so an unverified click never earns a mark.
nonisolated enum ClickReactionVerifier {
    // MARK: Reaction and Snapshot

    /// What the owner was observed to do.
    enum Reaction: Equatable {
        /// The owner put a new window on screen. The associated window is
        /// the best candidate for the interface the click opened.
        case openedInterface(CGWindowID)

        /// The item's own window changed size or left the screen.
        case itemChanged

        /// Nothing observable happened. Not proof of failure, see the
        /// type's discussion.
        case unobserved

        /// Whether the owner was seen doing anything at all.
        var didReact: Bool {
            self != .unobserved
        }
    }

    /// The observable state of the world immediately before a click.
    struct Snapshot {
        /// Every process that could plausibly own the reaction.
        ///
        /// Owner and source both count, since helper-hosted items are common.
        let pids: Set<pid_t>

        /// The item's own window.
        let itemWindowID: CGWindowID

        /// The item's bounds before the click.
        let itemBounds: CGRect

        /// Whether the item's window was on screen before the click. A
        /// concealed item's synthetic window never is, so its absence proves nothing.
        let itemWindowWasOnScreen: Bool

        /// Every on-screen window at snapshot time, so a window that was
        /// already open is not mistaken for one the click opened.
        let onScreenWindowIDs: Set<CGWindowID>
    }

    // MARK: Tuning

    /// How long to wait for a reaction. Real menus open well inside this; it
    /// only elapses when nothing happens, and bounds a wedged owner.
    private static let budget = Duration.milliseconds(250)

    /// How often to look while waiting.
    private static let pollInterval = Duration.milliseconds(20)

    /// How much the item's own window has to change before it counts.
    ///
    /// Sub-point differences are rounding in the window server's bounds,
    /// not a redraw.
    private static let boundsEpsilon: CGFloat = 1

    // MARK: Observing

    /// Captures the state a reaction will be measured against.
    ///
    /// Must be called before the click is posted.
    static func snapshot(for item: MenuBarItem) -> Snapshot {
        Snapshot(
            pids: item.reactionPIDs,
            itemWindowID: item.windowID,
            itemBounds: item.bounds,
            itemWindowWasOnScreen: Bridging.isWindowOnScreen(item.windowID),
            onScreenWindowIDs: Set(Bridging.getWindowList(option: .onScreen))
        )
    }

    /// Waits for the owner to react, returning as soon as it does.
    ///
    /// Call after the click is posted and the cursor restored, so the caller's
    /// own overlay work has settled and the signal is the owner's.
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

    /// One look at the world. Returns nil when it is still too early to
    /// say, and a reaction once there is something to report.
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

    /// Picks the window that best represents what the click opened. Split out
    /// from observe(_:) so it is testable without a window server.
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
        // Prefer a menu-level window; any other new owner window still counts.
        return owned.first(where: \.isMenuRelated) ?? owned.first
    }

    /// Whether an item's own window changed in a way only the owner could
    /// have caused.
    ///
    /// Only size is compared; the origin moves whenever the bar reflows.
    ///
    /// - Parameters:
    ///   - before: The item's bounds at snapshot time.
    ///   - after: The item's bounds now, or nil if its window is gone.
    static func itemChanged(from before: CGRect, to after: CGRect?) -> Bool {
        guard let after else {
            // The window is gone. Either the owner removed the item or it
            // was replaced, both are the owner acting.
            return true
        }
        return abs(after.width - before.width) > boundsEpsilon ||
            abs(after.height - before.height) > boundsEpsilon
    }

    private static func itemChanged(_ snapshot: Snapshot) -> Bool {
        // Nothing to compare against: only a new window can show a reaction.
        guard snapshot.itemWindowWasOnScreen else {
            return false
        }
        guard Bridging.isWindowOnScreen(snapshot.itemWindowID) else {
            return true
        }
        return itemChanged(from: snapshot.itemBounds, to: Bridging.getWindowBounds(for: snapshot.itemWindowID))
    }
}

nonisolated extension MenuBarItem {
    /// Every process that could own a reaction to this item: its owner and,
    /// for helper-hosted items, the source.
    var reactionPIDs: Set<pid_t> {
        Set([ownerPID, sourcePID].compactMap(\.self))
    }
}
