//
//  MenuBarItemManager+EventHelpers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency retained: CoreGraphics event types (CGEventSource/CGEvent) are
// still not Sendable-annotated in the macOS 26/27 SDK, yet are used off the main
// actor under OSAllocatedUnfairLock for menu-bar event posting. Removing the shim
// would force @unchecked Sendable wrappers. Drop this once Apple annotates them.
@preconcurrency import CoreGraphics
import MenuBarModel
import os.lock
import ThawConcurrency

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// Something went wrong while driving a menu bar item with synthetic events.
    ///
    /// The cases split along one line that matters downstream: a few of them
    /// mean the item's owner was handed events and stayed silent, and the rest
    /// mean Thaw never got as far as asking. See indicatesUnresponsiveOwner.
    enum EventError: CustomStringConvertible, LocalizedError {
        /// Nothing more specific is known.
        case cannotComplete
        /// No event source could be obtained to post through.
        case invalidEventSource
        /// The pointer's location could not be read.
        case missingMouseLocation
        /// Core Graphics refused to build one of the events.
        case eventCreationFailure(MenuBarItem)
        /// The owner never acknowledged an event within the allotted time.
        case eventOperationTimeout(MenuBarItem)
        /// The item is one the window server will not let Thaw rearrange.
        ///
        /// Carries why when the refusal came from an orderability check;
        /// nil where the error is raised on a path that has no reason in
        /// hand. See MenuBarItem.orderabilityRefusal(experimentalSystemItemHiding:).
        case itemNotMovable(MenuBarItem, MenuBarItem.OrderabilityRefusal?)
        /// The item took longer to react than the caller was willing to wait.
        case itemResponseTimeout(MenuBarItem)
        /// The item's on-screen rectangle could not be resolved.
        case missingItemBounds(MenuBarItem)
        /// Every anchor the move was planned against, the primary one and the
        /// alternates recorded beside it at drop time, disappeared between
        /// planning and execution. The bar moved under us; nothing has been
        /// learned about the item itself, so this case is deliberately
        /// environmental and catch sites must not write a persisted verdict
        /// from it.
        case destinationAnchorLost(MenuBarItem)

        /// Everything a case has to be able to say about itself: a token for
        /// logs, a sentence for the user, the item it happened to, and, for
        /// the one case that subdivides, which refusal it was.
        ///
        /// Answering all of these from one switch keeps them from drifting
        /// apart as cases come and go.
        private var report: (token: String, sentence: String, item: MenuBarItem?, reason: String?) {
            switch self {
            case .cannotComplete:
                return ("cannotComplete", "The operation did not run to completion", nil, nil)
            case .invalidEventSource:
                return ("invalidEventSource", "No usable event source", nil, nil)
            case .missingMouseLocation:
                return ("missingMouseLocation", "The pointer's location is unavailable", nil, nil)
            case let .eventCreationFailure(item):
                return ("eventCreationFailure", "No event could be built for “\(item.displayName)”", item, nil)
            case let .eventOperationTimeout(item):
                return ("eventOperationTimeout", "Posting events to “\(item.displayName)” ran out of time", item, nil)
            case let .itemNotMovable(item, refusal):
                let sentence = switch refusal {
                case .hiddenControlItem:
                    String(localized: "“\(item.displayName)” is one of Thaw’s own control items and cannot be moved")
                case .systemAnchored:
                    String(localized: "“\(item.displayName)” is anchored by macOS and cannot be moved")
                case .requiresExperimentalHiding:
                    String(localized: "“\(item.displayName)” can’t be moved until “Allow hiding macOS system items” is turned on in Layout settings")
                case .notAgentManaged:
                    String(localized: "“\(item.displayName)” is placed by macOS itself and cannot be moved")
                case .nativeOverflowControl:
                    String(localized: "“\(item.displayName)” is macOS’s overflow arrow, not a menu bar item, and cannot be moved")
                case nil:
                    "“\(item.displayName)” cannot be moved"
                }
                return (
                    "itemNotMovable",
                    sentence,
                    item,
                    refusal.map { String(describing: $0) }
                )
            case let .itemResponseTimeout(item):
                return ("itemResponseTimeout", "“\(item.displayName)” never answered", item, nil)
            case let .missingItemBounds(item):
                return ("missingItemBounds", "“\(item.displayName)” has no known bounds", item, nil)
            case let .destinationAnchorLost(item):
                return (
                    "destinationAnchorLost",
                    String(localized: "“\(item.displayName)” could not be placed. The items it was dropped beside have disappeared"),
                    item,
                    nil
                )
            }
        }

        var description: String {
            let form = report
            guard let item = form.item else {
                return "\(Self.self).\(form.token)"
            }
            // The refusal token stays part of this line so existing log-diffing
            // and saved searches on itemNotMovable keep matching; the reason
            // rides along instead of replacing it.
            let reason = form.reason.map { ", reason: \($0)" } ?? ""
            return "\(Self.self).\(form.token)(item: \(item.tag)\(reason))"
        }

        var errorDescription: String? {
            report.sentence
        }

        /// Whether this failure means the item's owner never acknowledged
        /// the events we posted.
        ///
        /// Only failures that are specifically about the owner staying
        /// silent count. cannotComplete is deliberately excluded: it is
        /// the catch-all, and attributing it to the owner would mark items
        /// over failures that had nothing to do with them.
        var indicatesUnresponsiveOwner: Bool {
            switch self {
            case .eventOperationTimeout, .itemResponseTimeout:
                true
            case .cannotComplete, .invalidEventSource, .missingMouseLocation,
                 .eventCreationFailure, .itemNotMovable, .missingItemBounds,
                 .destinationAnchorLost:
                false
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case let .itemNotMovable(_, refusal):
                // For every reason but one there is nothing to retry: the item
                // is pinned by the system, and trying again will land in
                // exactly the same place. The gate-dependent refusal is the
                // exception, the user can lift it in Settings, but the
                // suggestion deliberately stops short of promising the move
                // will then succeed, because the assertion path behind the
                // gate is experimental.
                guard refusal == .requiresExperimentalHiding else { return nil }
                return String(localized: "Turning on “Allow hiding macOS system items” in Layout settings may let this item move; macOS may still refuse it.")
            default:
                return "Try again. If this keeps happening, please file a bug report."
            }
        }
    }

    // MARK: Waiting

    /// The input-idle window a synthetic cursor move requires. Configurable
    /// escape hatch ported from the Thaw 2 move path (there
    /// inputPauseThresholdMs, default 50 ms): users hit by cursor kidnapping
    /// during reordering can widen it via
    /// defaults write <bundle-id> InputPauseThresholdMs -int <milliseconds>.
    static nonisolated var inputPauseThreshold: Duration {
        Duration.milliseconds(max(
            0,
            Defaults.integer(forKey: .inputPauseThresholdMs)
        ))
    }

    /// Whether the user's hands have been off the pointer for at least
    /// duration.
    ///
    /// A held modifier, a held button, a recent move, and a recent scroll all
    /// count as the user still driving. Synthetic events posted on top of real
    /// input get interleaved with it, so callers wait for all four to go quiet.
    ///
    /// - Parameter duration: How far back the movement and scroll history has
    ///   to be clear.
    nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        guard NSEvent.modifierFlags.isEmpty, !MouseHelpers.isButtonPressed() else {
            return false
        }
        return !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration)
    }

    /// Blocks until the user stops touching the pointer.
    ///
    /// The poll window and the poll interval are deliberately the same length:
    /// checking more often than the window it inspects only re-reads history
    /// that cannot have changed its answer yet.
    nonisolated func waitForUserToPauseInput() async throws {
        let pollWindow = Self.inputPauseThreshold
        let poll = Task {
            while !Task.isCancelled {
                if hasUserPausedInput(for: Self.inputPauseThreshold) {
                    return
                }
                try await Task.sleep(for: pollWindow)
            }
        }
        do {
            try await poll.value
        } catch {
            // Cancelled or interrupted; callers only ever need to know that
            // the wait did not finish.
            throw EventError.cannotComplete
        }
    }

    /// Bounded variant of waitForUserToPauseInput() for paths that must
    /// proceed even when the user never goes idle: a pane-edit pass the user
    /// is actively waiting on cannot stall behind a hand that never stops
    /// moving. Past the bound the warp happens anyway: briefly taking a moving
    /// cursor is better than hanging the user's edit.
    ///
    /// - Parameter timeout: How long to wait for the pause before giving up;
    ///   nil waits unboundedly (cancellation ends the wait).
    /// - Returns: Whether the user actually paused within the bound.
    nonisolated func waitForUserToPauseInput(timeout: Duration?) async -> Bool {
        let deadline = timeout.map { ContinuousClock.now + $0 }
        while !Task.isCancelled {
            if hasUserPausedInput(for: Self.inputPauseThreshold) {
                return true
            }
            if let deadline, ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Holds off until at least 25 ms have elapsed since the last move.
    ///
    /// Moves that land back-to-back race the window server's own bookkeeping,
    /// so a move arriving inside that gap waits out whatever is left of it. The
    /// first move of a session, and any move that is already late enough, waits
    /// for nothing.
    nonisolated func waitForMoveOperationBuffer() async throws {
        guard let lastMove = await moveActivity.lastInstant else {
            return
        }
        let remaining = max(.milliseconds(25) - lastMove.duration(to: .now), .zero)
        MenuBarItemManager.diagLog.debug("Holding \(remaining) before the next move operation")
        do {
            try await Task.sleep(for: remaining)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Pauses for duration, out of reach of cancellation.
    ///
    /// The gaps between posted events are part of the sequence the window
    /// server is being walked through. Dropping one because the surrounding
    /// task was cancelled would leave that sequence half-finished, so the sleep
    /// runs in a task of its own, which does not inherit the cancellation.
    nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let sleeper = Task {
            try? await Task.sleep(for: duration)
        }
        await sleeper.value
    }

    // MARK: Item Geometry

    /// Returns the current bounds for the given item, from a fresh AX enumeration.
    ///
    /// macOS 27 status items carry synthetic window IDs, so a WindowServer
    /// geometry lookup always fails; the AX walk is the only source of truth
    /// for item frames on this OS.
    nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
        return try Self.currentBounds(for: item, among: refreshed)
    }

    static nonisolated func currentBounds(for item: MenuBarItem, among refreshed: [MenuBarItem]) throws -> CGRect {
        if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone && !$0.isNativeOverflowControl }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) }) ??
            nearestSameOwnerMatch(for: item, in: refreshed)
        {
            return refreshedItem.bounds
        }
        throw EventError.missingItemBounds(item)
    }

    /// Re-resolves a live-updating item whose tag and window ID both change
    /// under us. Some apps rewrite their status-item title every second, and on
    /// macOS 27 the synthetic window ID derives from that title (see
    /// MenuBarItemTag), so a fresh enumeration matches neither.
    ///
    /// Position is the only stable signal: in the sub-second between
    /// enumeration and drag the item has not moved, so the same owner's item
    /// nearest the original X is the same logical item. Restricted to
    /// volatile-title third-party items; system items share one namespace and
    /// owning PID, so positional guessing would conflate them, and their stable
    /// titles already resolve through the title-based fallbacks.
    private static nonisolated func nearestSameOwnerMatch(
        for item: MenuBarItem,
        in refreshed: [MenuBarItem]
    ) -> MenuBarItem? {
        guard !item.tag.isNonConcealableSystemItem else { return nil }
        guard item.bounds.width > 0 else { return nil }
        let tolerance = max(item.bounds.width, 24)
        return refreshed
            .filter { $0.hasSameOwner(as: item) && !$0.isSystemClone && !$0.isNativeOverflowControl }
            .filter { abs($0.bounds.minX - item.bounds.minX) <= tolerance }
            .min { abs($0.bounds.minX - item.bounds.minX) < abs($1.bounds.minX - item.bounds.minX) }
    }

    // MARK: Event Plumbing

    /// Where the pointer is right now, in Core Graphics coordinates.
    ///
    /// Callers stash this before warping the cursor onto an item so they can
    /// put it back where the user left it.
    nonisolated func getMouseLocation() throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw EventError.missingMouseLocation
        }
        return location
    }

    /// The process that actually vends item, and therefore the one that
    /// events and Accessibility queries have to be addressed to.
    ///
    /// Items handed over by a host process report an owner that is not the
    /// process listening for them, so a known source PID wins. During startup
    /// the source has not been resolved yet and the owner is all there is.
    nonisolated func resolvedPID(for item: MenuBarItem) -> pid_t {
        item.sourcePID ?? item.ownerPID
    }

    /// The event source for stateID, built once and then reused.
    ///
    /// Suppression settings live on the source rather than on the events posted
    /// through it, so rebuilding a source per event would silently discard what
    /// stopSuppressingLocalEvents() configured. The cache is read and
    /// written under separate lock acquisitions on purpose: CGEventSource is
    /// a system call and is not made while holding the lock.
    nonisolated func getEventSource(
        with stateID: CGEventSourceStateID = .hidSystemState
    ) throws -> CGEventSource {
        enum Context {
            static let cache = OSAllocatedUnfairLock(initialState: [CGEventSourceStateID: CGEventSource]())
        }
        if let source = Context.cache.withLock({ $0[stateID] }) {
            return source
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError.invalidEventSource
        }
        Context.cache.withLock { $0[stateID] = source }
        return source
    }

    /// Clears the filters that would otherwise swallow local events while
    /// Thaw's own events are in flight.
    ///
    /// Posting a synthetic event puts the session into a suppression state, and
    /// by default that state drops the very events being posted. Both states
    /// that can apply here are opened up, and the interval that would keep them
    /// suppressed afterwards is zeroed.
    nonisolated func stopSuppressingLocalEvents() throws {
        let source = try getEventSource(with: .combinedSessionState)
        let suppressionStates: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in suppressionStates {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }

    // MARK: Continuation Boxes

    private nonisolated func storeInnerTask(
        _ task: Task<Void, Never>,
        in holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) {
        holder.withLock { $0 = task }
    }

    private nonisolated func currentInnerTask(
        from holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) -> Task<Void, Never>? {
        holder.withLock { $0 }
    }

    /// The unchanging half of a barrier run: the event being delivered, the
    /// marker events that bracket it, and the two places they are posted to.
    private nonisolated struct EventContinuationContext {
        let event: CGEvent
        let pid: pid_t
        let entryEvent: CGEvent
        let exitEvent: CGEvent
        /// The item owner's own event queue, where the markers are posted.
        let ownerLocation: EventTap.Location
        /// The session tap, where the real event is posted and observed.
        let sessionLocation: EventTap.Location
    }

    /// The mutable half, shared between the taps, the inner task, and the
    /// cancellation handler.
    ///
    /// outcome settles the run exactly once, whichever of the exit marker or
    /// a cancellation gets there first. A cancellation that arrives before the
    /// body has registered its continuation is kept and delivered on
    /// registration, so it can never be dropped and leave the run waiting.
    private nonisolated struct EventContinuationState {
        let countHolder: OSAllocatedUnfairLock<Int>
        let outcome: OneShotContinuation<Void, any Error>
        let innerTaskHolder: OSAllocatedUnfairLock<Task<Void, Never>?>
    }

    private nonisolated func decrementCount(
        in holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock {
            $0 -= 1
            return $0
        }
    }

    private nonisolated func currentCount(
        from holder: OSAllocatedUnfairLock<Int>
    ) -> Int {
        holder.withLock { $0 }
    }

    private nonisolated func makeContinuationTask(
        eventTaps: [EventTap],
        entryEvent: CGEvent,
        ownerLocation: EventTap.Location
    ) -> Task<Void, Never> {
        Task {
            for eventTap in eventTaps {
                eventTap.enable()
            }
            entryEvent.post(to: ownerLocation)
        }
    }

    // MARK: Barrier Taps

    private nonisolated func makeMenuBarItemEventTap(
        label: String,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        context: EventContinuationContext,
        onMatch: @escaping (EventTap) -> Void
    ) -> EventTap {
        EventTap(
            label: label,
            type: context.event.type,
            location: location,
            placement: placement,
            option: .listenOnly
        ) { tap, rEvent in
            guard rEvent.matches(context.event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                return rEvent
            }
            onMatch(tap)
            // Defensive: Since this EventTap is created with option: .listenOnly,
            // mutating rEvent via setTargetPID is for parity only and will not
            // affect the system event stream.
            rEvent.setTargetPID(context.pid)
            return rEvent
        }
    }

    /// The tap on the owner's queue, which watches for the two marker events
    /// and swallows both so the owner never sees them.
    ///
    /// The entry marker arriving means the owner has drained everything ahead
    /// of it, which is the moment the real event can go out. The exit marker
    /// arriving means the run is over.
    private nonisolated func makeEntryEventTap(
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        EventTap(
            label: "EventTap 1",
            type: .null,
            location: context.ownerLocation,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { tap, rEvent in
            if rEvent.matches(context.entryEvent, byIntegerFields: [.eventSourceUserData]) {
                _ = self.decrementCount(in: state.countHolder)
                context.event.post(to: context.sessionLocation)
                return nil
            }
            if rEvent.matches(context.exitEvent, byIntegerFields: [.eventSourceUserData]) {
                tap.disable()
                state.outcome.settle(.success(()))
                return nil
            }
            return rEvent
        }
    }

    /// The listener on the session tap, which sees the real event come back
    /// around and decides whether to go another round or close the run out.
    private nonisolated func makeSessionEventTap(
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 2",
            location: context.sessionLocation,
            placement: .tailAppendEventTap,
            context: context
        ) { tap in
            if self.currentCount(from: state.countHolder) <= 0 {
                tap.disable()
                context.exitEvent.post(to: context.ownerLocation)
            } else {
                context.entryEvent.post(to: context.ownerLocation)
            }
        }
    }

    private nonisolated func makeContinuationEventTaps(
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> [EventTap] {
        [
            makeEntryEventTap(
                context: context,
                state: state
            ),
            makeSessionEventTap(
                context: context,
                state: state
            ),
        ]
    }

    private nonisolated func awaitEventContinuation(
        context: EventContinuationContext,
        state: EventContinuationState,
        eventTaps: inout [EventTap]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            state.outcome.setContinuation(continuation)

            let continuationEventTaps = makeContinuationEventTaps(
                context: context,
                state: state
            )
            eventTaps.append(contentsOf: continuationEventTaps)

            let innerTask = makeContinuationTask(
                eventTaps: continuationEventTaps,
                entryEvent: context.entryEvent,
                ownerLocation: context.ownerLocation
            )
            storeInnerTask(innerTask, in: state.innerTaskHolder)
            if Task.isCancelled {
                innerTask.cancel()
            }
        }
    }

    // MARK: Barrier Operation

    /// Assembles everything a barrier run needs before any tap exists: the two
    /// marker events, the two locations they travel between, and the boxes the
    /// taps use to talk back to the continuation.
    ///
    /// event is stamped with its destination process here so that the taps
    /// are built against an event already in its final form.
    private nonisolated func prepareEventContinuation(
        for event: CGEvent,
        item: MenuBarItem,
        repeating count: Int
    ) throws -> (context: EventContinuationContext, state: EventContinuationState) {
        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = resolvedPID(for: item)
        event.setTargetPID(pid)

        let context = EventContinuationContext(
            event: event,
            pid: pid,
            entryEvent: entryEvent,
            exitEvent: exitEvent,
            ownerLocation: .pid(pid),
            sessionLocation: .sessionEventTap
        )
        let state = EventContinuationState(
            countHolder: OSAllocatedUnfairLock(initialState: count),
            outcome: OneShotContinuation<Void, any Error>(),
            innerTaskHolder: OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        )
        return (context, state)
    }

    /// Runs one barrier: post the event, wait for the owner to acknowledge it,
    /// and tear the taps down whichever way the run ends.
    private nonisolated func performEventContinuationOperation(
        event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int
    ) async throws {
        // The events below are posted at coordinates the pointer is not really
        // at, so the cursor is parked out of sight for the whole run rather
        // than left to flicker across the menu bar as they land.
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        let (context, state) = try prepareEventContinuation(
            for: event,
            item: item,
            repeating: count
        )

        // Every repetition gets the full timeout: a run of count events must
        // not be cut short by the budget meant for a single one.
        let timeoutTask = Task(timeout: timeout * count) {
            var eventTaps = [EventTap]()
            defer {
                for tap in eventTaps {
                    tap.invalidate()
                }
            }
            try await withTaskCancellationHandler {
                try await awaitEventContinuation(
                    context: context,
                    state: state,
                    eventTaps: &eventTaps
                )
            } onCancel: {
                currentInnerTask(from: state.innerTaskHolder)?.cancel()
                // Settle here as well. Cancellation routinely arrives after the
                // inner task has already finished, and cancelling a task that
                // is already done wakes nobody. Settling before the body has
                // registered is fine: the result waits for it.
                state.outcome.settle(.failure(CancellationError()))
            }
        }

        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Posts an event to the given menu bar item and waits until
    /// it is received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by count to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling postEventWithBarrier.
    nonisolated func postEventWithBarrier(
        _ event: CGEvent,
        to item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        try await performEventContinuationOperation(
            event: event,
            item: item,
            timeout: timeout,
            repeating: count
        )
    }
}
