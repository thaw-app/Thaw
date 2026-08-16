//
//  MenuBarItemManager+EventHelpers.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics
import os.lock

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    enum EventError: CustomStringConvertible, LocalizedError {
        /// A generic indication of a failure.
        case cannotComplete
        /// An event source cannot be created or is otherwise invalid.
        case invalidEventSource
        /// The location of the mouse cannot be found.
        case missingMouseLocation
        /// A failure during the creation of an event.
        case eventCreationFailure(MenuBarItem)
        /// A timeout during an event operation.
        case eventOperationTimeout(MenuBarItem)
        /// A menu bar item is not movable.
        case itemNotMovable(MenuBarItem)
        /// A timeout waiting for a menu bar item to respond to an event.
        case itemResponseTimeout(MenuBarItem)
        /// A menu bar item's bounds cannot be found.
        case missingItemBounds(MenuBarItem)
        /// A menu bar item's menu is tracking (e.g. the Wi-Fi picker or an
        /// input method panel is open) and the move was deferred.
        case menuTrackingActive(MenuBarItem)
        /// A menu bar item's owning process is alive but not pumping its
        /// event loop, so it cannot acknowledge synthetic move events.
        case ownerUnresponsive(MenuBarItem)
        /// A synthetic event came back through the session tap carrying a
        /// different window than the one it was addressed to, meaning the
        /// window server re-resolved it against whatever sits under the
        /// clamped cursor position.
        case eventWindowMismatch(MenuBarItem)
        /// The destination's target item moved so far during the drag that
        /// the plan describes an arrangement the bar no longer has. Retrying
        /// would drag the item against geometry that has already changed,
        /// which is how a failed batch walks the bar (#900).
        case staleDestination(MenuBarItem)

        var description: String {
            switch self {
            case .cannotComplete:
                "\(Self.self).cannotComplete"
            case .invalidEventSource:
                "\(Self.self).invalidEventSource"
            case .missingMouseLocation:
                "\(Self.self).missingMouseLocation"
            case let .eventCreationFailure(item):
                "\(Self.self).eventCreationFailure(item: \(item.tag))"
            case let .eventOperationTimeout(item):
                "\(Self.self).eventOperationTimeout(item: \(item.tag))"
            case let .itemNotMovable(item):
                "\(Self.self).itemNotMovable(item: \(item.tag))"
            case let .itemResponseTimeout(item):
                "\(Self.self).itemResponseTimeout(item: \(item.tag))"
            case let .missingItemBounds(item):
                "\(Self.self).missingItemBounds(item: \(item.tag))"
            case let .menuTrackingActive(item):
                "\(Self.self).menuTrackingActive(item: \(item.tag))"
            case let .ownerUnresponsive(item):
                "\(Self.self).ownerUnresponsive(item: \(item.tag))"
            case let .eventWindowMismatch(item):
                "\(Self.self).eventWindowMismatch(item: \(item.tag))"
            case let .staleDestination(item):
                "\(Self.self).staleDestination(item: \(item.tag))"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                "Operation could not be completed"
            case .invalidEventSource:
                "Invalid event source"
            case .missingMouseLocation:
                "Missing mouse location"
            case let .eventCreationFailure(item):
                "Could not create event for \"\(item.displayName)\""
            case let .eventOperationTimeout(item):
                "Event operation timed out for \"\(item.displayName)\""
            case let .itemNotMovable(item):
                "\"\(item.displayName)\" is not movable"
            case let .itemResponseTimeout(item):
                "\"\(item.displayName)\" took too long to respond"
            case let .missingItemBounds(item):
                "Missing bounds rectangle for \"\(item.displayName)\""
            case let .menuTrackingActive(item):
                "A menu bar item's menu was open while moving \"\(item.displayName)\""
            case let .ownerUnresponsive(item):
                "\"\(item.displayName)\" is not responding and cannot be moved"
            case let .eventWindowMismatch(item):
                "A move event for \"\(item.displayName)\" was delivered to the wrong window"
            case let .staleDestination(item):
                "The menu bar rearranged while moving \"\(item.displayName)\""
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self {
                return nil
            }
            return "Please try again. If the error persists, please file a bug report."
        }

        /// How the failure ledger should file this error.
        var failureKind: MenuBarItemFailureLedger.FailureKind {
            indicatesUnresponsiveOwner ? .unresponsiveOwner : .other
        }

        /// Whether this failure means the item's owner never acknowledged
        /// the events we posted.
        ///
        /// Only failures that are specifically about the owner staying
        /// silent count. `cannotComplete` is deliberately excluded: it is
        /// the catch-all, and attributing it to the owner would mark items
        /// over failures that had nothing to do with them.
        var indicatesUnresponsiveOwner: Bool {
            switch self {
            case .ownerUnresponsive, .eventOperationTimeout, .itemResponseTimeout:
                true
            case .cannotComplete, .invalidEventSource, .missingMouseLocation, .eventCreationFailure,
                 .itemNotMovable, .missingItemBounds, .menuTrackingActive, .eventWindowMismatch,
                 .staleDestination:
                false
            }
        }
    }

    /// Returns a Boolean value that indicates whether the user has
    /// paused input for at least the given duration.
    ///
    /// - Parameter duration: The duration that certain types of input
    ///   events must not have occurred within in order to return `true`.
    nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
            !MouseHelpers.isButtonPressed()
    }

    /// Waits asynchronously for the user to pause input.
    nonisolated func waitForUserToPauseInput() async throws {
        // The pre-move input-pause window is configurable so users hit by repeated cursor
        // "kidnapping" during menu-bar reordering can widen it. Reordering warps the real cursor,
        // and a very short window lets warps slip through the micro-gaps between a user's own mouse
        // moves when a churny app keeps changing its menu-bar items (see #750, #723, #736). The
        // default preserves the previous 50 ms behaviour; override with:
        //   defaults write com.stonerl.Thaw inputPauseThresholdMs -int <milliseconds>
        let pauseMs = max(
            0,
            (Defaults.object(forKey: .inputPauseThresholdMs) as? Int) ?? Defaults.DefaultValue.inputPauseThresholdMs
        )
        let waitTask = Task {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: .milliseconds(pauseMs)) {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        do {
            try await waitTask.value
        } catch {
            // Only cancellation reaches here. Named so a log full of bare
            // `cannotComplete` failures (#900) can tell this stage apart.
            MenuBarItemManager.diagLog.debug("waitForUserInputPause: wait interrupted: \(error)")
            throw EventError.cannotComplete
        }
    }

    /// Waits for a lull in user input before an automatic bulk apply
    /// begins issuing its move sequence.
    ///
    /// `waitForUserToPauseInput` gates each move; this gates the batch. The
    /// distinction matters because a batch hides the cursor for its entire
    /// length: dispatched the moment a late arrival is noticed, it can take
    /// the pointer away mid-interaction and then contest it move by move
    /// for the length of the sequence (#899, #723). Waiting for one real
    /// lull up front costs nothing on an idle bar — the common case, where
    /// the first poll already passes — and sidesteps the collision when the
    /// bar is not idle.
    ///
    /// Deferring only. The cap guarantees the batch still runs, and
    /// cancellation exits promptly so a newer apply can replace this one;
    /// the caller re-checks `Task.isCancelled` immediately afterwards.
    ///
    /// On by default at 300 ms; disable with:
    ///   defaults write com.stonerl.Thaw bulkApplyIdleThresholdMs -int 0
    nonisolated func waitForBulkApplyIdleWindow() async {
        let thresholdMs = (Defaults.object(forKey: .bulkApplyIdleThresholdMs) as? Int)
            ?? Defaults.DefaultValue.bulkApplyIdleThresholdMs
        let capMs = (Defaults.object(forKey: .bulkApplyIdleWaitCapMs) as? Int)
            ?? Defaults.DefaultValue.bulkApplyIdleWaitCapMs
        guard let window = MenuBarItemManager.bulkApplyIdleWindow(
            thresholdMs: thresholdMs,
            capMs: capMs
        ) else {
            return
        }

        let start = ContinuousClock.now
        while !Task.isCancelled {
            let elapsed = ContinuousClock.now - start
            if MenuBarItemManager.bulkApplyIdleWaitConcluded(
                userHasPausedInput: hasUserPausedInput(for: window.threshold),
                elapsed: elapsed,
                cap: window.cap
            ) {
                if elapsed >= window.cap {
                    MenuBarItemManager.diagLog.debug(
                        "Bulk apply idle gate: cap reached after \(elapsed.milliseconds) ms without a lull; proceeding anyway"
                    )
                } else if elapsed > .zero {
                    MenuBarItemManager.diagLog.debug(
                        "Bulk apply idle gate: waited \(elapsed.milliseconds) ms for input to settle"
                    )
                }
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return // Cancelled; the caller's Task.isCancelled check handles it.
            }
        }
    }

    /// Waits between move operations for a dynamic amount of time,
    /// based on the timestamp of the last move operation.
    nonisolated func waitForMoveOperationBuffer() async throws {
        if let timestamp = await lastMoveOperationTimestamp {
            let buffer = max(.milliseconds(25) - timestamp.duration(to: .now), .zero)
            MenuBarItemManager.diagLog.debug("Move operation buffer: \(buffer)")
            do {
                try await Task.sleep(for: buffer)
            } catch {
                MenuBarItemManager.diagLog.debug("waitForMoveOperationBuffer: wait interrupted: \(error)")
                throw EventError.cannotComplete
            }
        }
    }

    /// Waits for the given duration between event operations.
    ///
    /// Since most event operations must perform cleanup or otherwise
    /// run to completion, this method ignores task cancellation.
    nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    /// Returns the current bounds for the given item, with a refresh fallback if the window is missing.
    nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        // First attempt: current windowID.
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            return bounds
        }

        // Fallback: refresh on-screen items and pick the matching tag (prefer same windowID, then non-clone).
        let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
        if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        {
            return refreshedItem.bounds
        }

        throw EventError.missingItemBounds(item)
    }

    /// Returns the current mouse location.
    nonisolated func getMouseLocation() throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw EventError.missingMouseLocation
        }
        return location
    }

    /// Returns the process identifier that can be used to create
    /// and post a menu bar item event.
    nonisolated func getEventPID(for item: MenuBarItem) -> pid_t {
        Self.eventTargetPID(
            sourcePID: item.sourcePID,
            ownerPID: item.ownerPID,
            preferWindowOwner: MenuBarItem.postsMoveEventsToWindowOwner
        )
    }

    /// Whether a previously cached source PID still belongs to a live
    /// process.
    ///
    /// `kill(pid, 0)` is the same liveness probe `postMoveEvents` already
    /// makes before addressing a target, kept in one named place so the
    /// reconciliation guard and the event path agree about what "alive"
    /// means. `ESRCH` is the only answer that means gone; `EPERM` says the
    /// process exists but is not ours to signal, which still counts as
    /// alive.
    static nonisolated func previousPIDIsLive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    /// The process a synthetic move event should be posted to.
    ///
    /// `ownerPID` is the CG owner of the window being dragged. `sourcePID`
    /// is the app whose status item it logically is. Before macOS 26 these
    /// were the same process; on 26 Control Center hosts every status item
    /// window, so preferring `sourcePID` posts to a process that does not
    /// own the window under the cursor.
    ///
    /// Pure over its inputs.
    static nonisolated func eventTargetPID(
        sourcePID: pid_t?,
        ownerPID: pid_t,
        preferWindowOwner: Bool
    ) -> pid_t {
        if preferWindowOwner {
            return ownerPID
        }
        return sourcePID ?? ownerPID
    }

    /// Returns an event source for a menu bar item event operation.
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

    /// Prevents local events from being suppressed.
    nonisolated func permitLocalEvents() throws {
        let source = try getEventSource(with: .combinedSessionState)
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }

    private nonisolated func storeContinuation(
        _ continuation: CheckedContinuation<Void, any Error>,
        in holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) {
        holder.withLock { $0 = continuation }
    }

    private nonisolated func storeInnerTask(
        _ task: Task<Void, Never>,
        in holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) {
        holder.withLock { $0 = task }
    }

    private nonisolated func currentContinuation(
        from holder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
    ) -> CheckedContinuation<Void, any Error>? {
        holder.withLock { $0 }
    }

    private nonisolated func currentInnerTask(
        from holder: OSAllocatedUnfairLock<Task<Void, Never>?>
    ) -> Task<Void, Never>? {
        holder.withLock { $0 }
    }

    private nonisolated struct EventContinuationContext {
        let event: CGEvent
        let item: MenuBarItem
        let pid: pid_t
        let entryEvent: CGEvent
        let exitEvent: CGEvent
        let firstLocation: EventTap.Location
        let secondLocation: EventTap.Location
    }

    private nonisolated struct EventContinuationState {
        let countHolder: OSAllocatedUnfairLock<Int>
        let didResume: OSAllocatedUnfairLock<Bool>
        let continuationHolder: OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>
        let innerTaskHolder: OSAllocatedUnfairLock<Task<Void, Never>?>
    }

    private nonisolated enum EventContinuationKind {
        case postEventBarrier
        case scromble
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

    private nonisolated func disableEventTaps(_ eventTaps: [EventTap]) {
        for eventTap in eventTaps {
            eventTap.disable()
        }
    }

    private nonisolated func resumeCancellationIfNeeded(
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        if state.didResume.tryClaimOnce() {
            continuation.resume(throwing: CancellationError())
        }
    }

    /// Resumes the stored continuation by throwing `error`, if no other
    /// path has resumed it yet. Used to fail an in-flight event operation
    /// early instead of waiting out its timeout.
    private nonisolated func resumeFailureIfNeeded(
        state: EventContinuationState,
        error: any Error
    ) {
        let continuation = currentContinuation(from: state.continuationHolder)
        if let continuation, state.didResume.tryClaimOnce() {
            continuation.resume(throwing: error)
        }
    }

    /// Returns whether `rEvent` is a stray echo of this operation's own
    /// event: it carries the same `eventSourceUserData` — unique per posted
    /// event, so a positive identification — but its window fields no longer
    /// match the ones it was posted with.
    ///
    /// The window server re-resolves
    /// `mouseEventWindowUnderMousePointer*` against whatever actually sits
    /// under the cursor. For an item parked off the left edge, the posted
    /// coordinates get clamped to the display's leftmost edge — under the
    /// Apple menu — and the event comes back bound to that window instead.
    /// Left in the stream it is delivered there, which is what surfaces as a
    /// stray click at the top-left of the screen.
    private nonisolated func isStrayEcho(
        of rEvent: CGEvent,
        context: EventContinuationContext
    ) -> Bool {
        guard rEvent.matches(context.event, byIntegerFields: [.eventSourceUserData]) else {
            return false
        }
        return !rEvent.matches(context.event, byIntegerFields: CGEventField.menuBarItemEventFields)
    }

    /// Whether stray echoes of our own move events are dropped from the
    /// session stream before they can be delivered against the wrong window.
    ///
    /// On by default; this only ever discards events that are already
    /// misdirected — an echo whose window fields still match is passed
    /// through untouched, so the scromble handshake is unaffected. Kill
    /// switch, should it ever misfire:
    ///   defaults write com.stonerl.Thaw discardStrayMoveEvents -bool NO
    private nonisolated var discardsStrayMoveEvents: Bool {
        (Defaults.object(forKey: .discardStrayMoveEvents) as? Bool) ?? Defaults.DefaultValue.discardStrayMoveEvents
    }

    /// Whether a synthetic event that comes back addressed to a different
    /// window than it was posted with should fail its operation immediately
    /// rather than let it run to timeout.
    ///
    /// The mismatch is always logged; only the early failure is gated. The
    /// window server re-resolves the `mouseEventWindowUnderMousePointer*`
    /// fields against whatever actually sits under the cursor, so a mismatch
    /// is the signature of a move whose coordinates were clamped — the
    /// top-left/Apple-menu case for items parked off the left edge. Whether
    /// that is *always* unrecoverable is unverified on real hardware, hence
    /// the opt-in. Enable with:
    ///   defaults write com.stonerl.Thaw failFastOnEventWindowMismatch -bool YES
    private nonisolated var failsFastOnEventWindowMismatch: Bool {
        Defaults.bool(forKey: .failFastOnEventWindowMismatch)
    }

    private nonisolated func makeContinuationTask(
        eventTaps: [EventTap],
        entryEvent: CGEvent,
        firstLocation: EventTap.Location
    ) -> Task<Void, Never> {
        Task {
            for eventTap in eventTaps {
                eventTap.enable()
            }
            entryEvent.post(to: firstLocation)
        }
    }

    private nonisolated func makeEventTap(
        label: String,
        type: CGEventType,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        handler: @escaping (EventTap, CGEvent) -> CGEvent?
    ) -> EventTap {
        EventTap(
            label: label,
            type: type,
            location: location,
            placement: placement,
            option: option,
            callback: handler
        )
    }

    private nonisolated func makeMenuBarItemEventTap(
        label: String,
        location: EventTap.Location,
        placement: CGEventTapPlacement,
        context: EventContinuationContext,
        onMismatch: ((CGEvent) -> Void)? = nil,
        onMatch: @escaping (EventTap) -> Void
    ) -> EventTap {
        makeEventTap(
            label: label,
            type: context.event.type,
            location: location,
            placement: placement,
            option: .listenOnly
        ) { tap, rEvent in
            guard rEvent.matches(context.event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                // `eventSourceUserData` is unique per posted event (see
                // `setUserData`), so matching on it alone positively
                // identifies this operation's own event. Getting here with
                // that field equal means the event came back with the window
                // fields rewritten — it was delivered against a different
                // window than the one it addressed.
                if rEvent.matches(context.event, byIntegerFields: [.eventSourceUserData]) {
                    onMismatch?(rEvent)
                }
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

    private nonisolated func makeEntryEventTap(
        context: EventContinuationContext,
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) -> EventTap {
        makeEventTap(
            label: "EventTap 1",
            type: .null,
            location: context.firstLocation,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { tap, rEvent in
            if rEvent.matches(context.entryEvent, byIntegerFields: [.eventSourceUserData]) {
                _ = self.decrementCount(in: state.countHolder)
                context.event.post(to: context.secondLocation)
                return nil
            }
            if rEvent.matches(context.exitEvent, byIntegerFields: [.eventSourceUserData]) {
                tap.disable()
                if state.didResume.tryClaimOnce() {
                    continuation.resume()
                }
                return nil
            }
            return rEvent
        }
    }

    private nonisolated func makeSecondLocationEventTap(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 2",
            location: context.secondLocation,
            placement: .tailAppendEventTap,
            context: context,
            onMismatch: { [weak self] rEvent in
                guard let self else { return }
                let expected = context.event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
                let got = rEvent.getIntegerValueField(.mouseEventWindowUnderMousePointer)
                MenuBarItemManager.diagLog.warning(
                    """
                    Event for \(context.item.logString) came back on the wrong window \
                    (got \(got), expected \(expected)) at \(String(describing: rEvent.location))
                    """
                )
                if failsFastOnEventWindowMismatch {
                    resumeFailureIfNeeded(
                        state: state,
                        error: EventError.eventWindowMismatch(context.item)
                    )
                }
            },
            onMatch: { tap in
                switch kind {
                case .postEventBarrier:
                    if self.currentCount(from: state.countHolder) <= 0 {
                        tap.disable()
                        context.exitEvent.post(to: context.firstLocation)
                    } else {
                        context.entryEvent.post(to: context.firstLocation)
                    }
                case .scromble:
                    if self.currentCount(from: state.countHolder) <= 0 {
                        tap.disable()
                    }
                    context.event.post(to: context.firstLocation)
                }
            }
        )
    }

    private nonisolated func makeFirstLocationRelayEventTap(
        context: EventContinuationContext,
        state: EventContinuationState
    ) -> EventTap {
        makeMenuBarItemEventTap(
            label: "EventTap 3",
            location: context.firstLocation,
            placement: .headInsertEventTap,
            context: context
        ) { tap in
            if self.currentCount(from: state.countHolder) <= 0 {
                tap.disable()
                context.exitEvent.post(to: context.firstLocation)
            } else {
                context.entryEvent.post(to: context.firstLocation)
            }
        }
    }

    /// Creates a tap that removes stray echoes of this operation's own event
    /// from the session stream, so they cannot be delivered against the
    /// window the window server re-bound them to.
    ///
    /// Head-inserted and non-listen-only, so it runs before the tail-appended
    /// handshake taps and can actually drop the event. This is safe with
    /// respect to that handshake: those taps only act on echoes whose window
    /// fields still match, and such echoes are passed through here untouched.
    private nonisolated func makeStrayEventDiscardTap(
        context: EventContinuationContext
    ) -> EventTap {
        makeEventTap(
            label: "Stray move event discard",
            type: context.event.type,
            location: context.secondLocation,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { _, rEvent in
            guard self.isStrayEcho(of: rEvent, context: context) else {
                return rEvent
            }
            MenuBarItemManager.diagLog.debug(
                """
                Discarding stray echo of \(context.item.logString) move event \
                at \(String(describing: rEvent.location))
                """
            )
            return nil
        }
    }

    private nonisolated func makeContinuationEventTaps(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState,
        continuation: CheckedContinuation<Void, any Error>
    ) -> [EventTap] {
        var eventTaps = [EventTap]()
        if discardsStrayMoveEvents {
            let strayEventDiscardTap = makeStrayEventDiscardTap(context: context)
            if strayEventDiscardTap.isValid {
                eventTaps.append(strayEventDiscardTap)
            } else {
                MenuBarItemManager.diagLog.error(
                    """
                    Failed to create stray move event discard tap for \
                    \(context.item.logString); continuing without stray echo \
                    protection for this operation
                    """
                )
            }
        }
        eventTaps.append(
            contentsOf: [
                makeEntryEventTap(
                    context: context,
                    state: state,
                    continuation: continuation
                ),
                makeSecondLocationEventTap(
                    kind: kind,
                    context: context,
                    state: state
                ),
            ]
        )
        if kind == EventContinuationKind.scromble {
            eventTaps.append(
                makeFirstLocationRelayEventTap(
                    context: context,
                    state: state
                )
            )
        }
        return eventTaps
    }

    private nonisolated func awaitEventContinuation(
        kind: EventContinuationKind,
        context: EventContinuationContext,
        state: EventContinuationState,
        eventTaps: inout [EventTap]
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            storeContinuation(continuation, in: state.continuationHolder)

            let continuationEventTaps = makeContinuationEventTaps(
                kind: kind,
                context: context,
                state: state,
                continuation: continuation
            )
            eventTaps.append(contentsOf: continuationEventTaps)

            let innerTask = makeContinuationTask(
                eventTaps: continuationEventTaps,
                entryEvent: context.entryEvent,
                firstLocation: context.firstLocation
            )
            storeInnerTask(innerTask, in: state.innerTaskHolder)
            if Task.isCancelled {
                innerTask.cancel()
            }
        }
    }

    private nonisolated func performEventContinuationOperation(
        _ kind: EventContinuationKind,
        event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        let countHolder = OSAllocatedUnfairLock(initialState: count)

        let didResume = OSAllocatedUnfairLock(initialState: false)
        let continuationHolder = OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>(initialState: nil)
        let innerTaskHolder = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        let continuationContext = EventContinuationContext(
            event: event,
            item: item,
            pid: pid,
            entryEvent: entryEvent,
            exitEvent: exitEvent,
            firstLocation: firstLocation,
            secondLocation: secondLocation
        )
        let continuationState = EventContinuationState(
            countHolder: countHolder,
            didResume: didResume,
            continuationHolder: continuationHolder,
            innerTaskHolder: innerTaskHolder
        )

        let timeoutTask = Task(timeout: timeout * count) {
            var eventTaps = [EventTap]()
            defer {
                for tap in eventTaps {
                    tap.invalidate()
                }
            }
            try await withTaskCancellationHandler {
                try await awaitEventContinuation(
                    kind: kind,
                    context: continuationContext,
                    state: continuationState,
                    eventTaps: &eventTaps
                )
            } onCancel: {
                currentInnerTask(from: innerTaskHolder)?.cancel()
                // Directly resume the continuation; handles the common case where
                // innerTask already finished before cancellation was delivered.
                let cont = currentContinuation(from: continuationHolder)
                if let cont, didResume.tryClaimOnce() {
                    cont.resume(throwing: CancellationError())
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch let error as EventError {
            // Preserve failures raised from inside the continuation (e.g. a
            // window mismatch) so callers can tell them apart from a generic
            // failure and skip pointless retries.
            throw error
        } catch {
            // Cancellation of a superseded operation lands here. The
            // underlying error used to be discarded, leaving #900's log a
            // wall of indistinguishable `cannotComplete`s.
            MenuBarItemManager.diagLog.debug("postEvent: event wait for \(item.logString) failed: \(error)")
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
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `postEventWithBarrier`.
    nonisolated func postEventWithBarrier(
        _ event: CGEvent,
        to item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        try await performEventContinuationOperation(
            EventContinuationKind.postEventBarrier,
            event: event,
            item: item,
            timeout: timeout,
            repeating: count
        )
    }

    /// Casts forbidden magic to make a menu bar item receive and
    /// respond to an event during a move operation.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `scrombleEvent`.
    nonisolated func scrombleEvent(
        _ event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        try await performEventContinuationOperation(
            EventContinuationKind.scromble,
            event: event,
            item: item,
            timeout: timeout,
            repeating: count
        )
    }
}
