//
//  ClickReactionVerifier.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

// MARK: - ClickReactionVerifier

/// Watches for evidence that an owner actually *did* something after we
/// clicked one of its menu bar items.
///
/// Posting a click tells us the event was delivered and acknowledged. It
/// does not tell us the owner reacted to it. An app whose main thread is
/// wedged, or one that drops synthetic events because GUI Scripting is
/// disabled, still drains the event queue — the post succeeds, nothing
/// opens, and from the event layer that is indistinguishable from a click
/// that worked.
///
/// The distinction matters because success is what clears a standing
/// unresponsive mark. Without this, an owner that never reacts is
/// re-forgiven on every click, re-earns its mark on the next failure, and
/// the user watches the item jitter through a full retry loop each time.
///
/// ## What counts as a reaction
///
/// Only positive evidence is trusted:
///
/// - The owner put a new window on screen — a menu, a popover, a panel.
///   This is the common case and the strongest signal.
/// - The item's own window changed size or left the screen. Toggle-style
///   items that open nothing often redraw to a different width, and some
///   remove themselves outright.
///
/// The absence of both is explicitly *not* treated as proof of failure. A
/// mute toggle that flips a glyph inside a fixed-width window reacts
/// perfectly well and is invisible to every signal here. So an
/// unverified click is only denied the right to clear an existing mark;
/// it never earns one.
nonisolated enum ClickReactionVerifier {
    // MARK: Types

    /// What the owner was observed to do.
    enum Reaction: Equatable {
        /// The owner put a new window on screen. The associated window is
        /// the best candidate for the interface the click opened.
        case openedInterface(CGWindowID)

        /// The item's own window changed size or left the screen.
        case itemChanged

        /// Nothing observable happened. Not proof of failure — see the
        /// type's discussion.
        case unobserved

        /// Whether the owner was seen doing anything at all.
        var didReact: Bool {
            self != .unobserved
        }

        /// The window the click opened, if one was seen.
        var openedWindowID: CGWindowID? {
            if case let .openedInterface(windowID) = self {
                return windowID
            }
            return nil
        }
    }

    /// The observable state of the world immediately before a click.
    struct Snapshot {
        /// Every process that could plausibly own the reaction.
        ///
        /// An item's window and the app that reacts to it are not always
        /// the same process — helper-hosted items are common — so both
        /// the owner and the source are accepted.
        let pids: Set<pid_t>

        /// The item's own window.
        let itemWindowID: CGWindowID

        /// The item's bounds before the click.
        let itemBounds: CGRect

        /// Every on-screen window at snapshot time, so a window that was
        /// already open is not mistaken for one the click opened.
        let onScreenWindowIDs: Set<CGWindowID>
    }

    // MARK: Tuning

    /// How long to wait for a reaction before giving up.
    ///
    /// A menu that is going to open opens well inside this. The budget
    /// only elapses in full when nothing happens, which is exactly the
    /// case worth spending time on, and it is bounded so a wedged owner
    /// cannot stall the caller.
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
            pids: Set([item.ownerPID, item.sourcePID].compactMap(\.self)),
            itemWindowID: item.windowID,
            itemBounds: item.bounds,
            onScreenWindowIDs: Set(Bridging.getWindowList(option: .onScreen))
        )
    }

    /// Waits for the owner to react, returning as soon as it does.
    ///
    /// Must be called after the click has been posted and the cursor has
    /// been restored — a warped cursor does not affect the window list,
    /// but the caller's own overlay work can, and letting it settle first
    /// keeps the signal attributable to the owner.
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

    /// One look at the world, right now, without spending the budget.
    ///
    /// For a caller that has already waited — an accessibility action that
    /// blocked until its messaging timeout expired, say — the question is not
    /// "will the owner react" but "did it react while I was blocked", and that
    /// is answerable immediately. Waiting again would only add the budget to a
    /// latency the caller has already paid.
    ///
    /// - Returns: What the owner has been seen doing, or `nil` when nothing
    ///   has been seen yet. Unlike ``verify(against:)`` this does not settle
    ///   for ``Reaction/unobserved`` — it has not waited long enough to say
    ///   that.
    static func reactionSoFar(against snapshot: Snapshot) -> Reaction? {
        observe(snapshot)
    }

    /// One look at the world. Returns `nil` when it is still too early to
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

    /// Picks the window that best represents an interface the click
    /// opened, out of the windows that appeared while we watched.
    ///
    /// Split out from ``observe(_:)`` so the rule can be exercised
    /// without a live window server.
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
        // A menu-level window is the reaction we are looking for. Anything
        // else the owner happened to open in the same instant is weaker
        // evidence, but it is still the owner doing something, so it is
        // accepted rather than discarded.
        return owned.first(where: \.isMenuRelated) ?? owned.first
    }

    /// Whether an item's own window changed in a way only the owner could
    /// have caused.
    ///
    /// Only the size is compared. An item's origin moves whenever a
    /// neighbor appears or the menu bar reflows, none of which says
    /// anything about our click.
    ///
    /// - Parameters:
    ///   - before: The item's bounds at snapshot time.
    ///   - after: The item's bounds now, or `nil` if its window is gone.
    static func itemChanged(from before: CGRect, to after: CGRect?) -> Bool {
        guard let after else {
            // The window is gone. Either the owner removed the item or it
            // was replaced — both are the owner acting.
            return true
        }
        return abs(after.width - before.width) > boundsEpsilon ||
            abs(after.height - before.height) > boundsEpsilon
    }

    private static func itemChanged(_ snapshot: Snapshot) -> Bool {
        guard Bridging.isWindowOnScreen(snapshot.itemWindowID) else {
            // Off-screen now. That is the owner acting only if the window
            // was on screen when the snapshot was taken — an ID that was
            // already stale then tells us nothing about our click, and
            // reading it as a reaction reports success for an item we
            // never actually observed.
            return snapshot.onScreenWindowIDs.contains(snapshot.itemWindowID)
        }
        return itemChanged(from: snapshot.itemBounds, to: Bridging.getWindowBounds(for: snapshot.itemWindowID))
    }
}
