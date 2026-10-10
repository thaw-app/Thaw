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
    enum InputPauseWaitResult {
        case paused
        case timedOut
        case superseded
    }

    /// An error that can occur during menu bar item event operations.
    enum EventError: CustomStringConvertible, LocalizedError {
        /// A generic indication of a failure.
        case cannotComplete
        /// An event source cannot be created or is otherwise invalid.
        case invalidEventSource
        case missingMouseLocation
        case eventCreationFailure(MenuBarItem)
        case eventOperationTimeout(MenuBarItem)
        case itemNotMovable(MenuBarItem)
        /// A timeout waiting for a menu bar item to respond to an event.
        case itemResponseTimeout(MenuBarItem)
        case missingItemBounds(MenuBarItem)
        /// The destination anchor disappeared before the move could use it.
        /// This is a stale plan, not a failure of the item being moved.
        case missingDestinationBounds(MenuBarItem)
        /// A menu bar item's menu is tracking (e.g. the Wi-Fi picker or an
        /// input method panel is open) and the move was deferred.
        case menuTrackingActive(MenuBarItem)
        /// A menu bar item's owning process is alive but not pumping its
        /// event loop, so it cannot acknowledge synthetic move events.
        case ownerUnresponsive(MenuBarItem)
        /// The event came back with a different window than it was addressed to:
        /// WindowServer re-resolved it against whatever is under the clamped cursor.
        case eventWindowMismatch(MenuBarItem)
        /// The destination moved so far mid-drag that the plan no longer matches
        /// the bar. Retrying against changed geometry walks the bar (#900).
        case staleDestination(MenuBarItem)
        /// The user didn't pause input before the deadline. Trigger moves defer
        /// instead of taking the cursor mid-interaction.
        case inputPauseTimedOut(MenuBarItem)
        /// The condition which requested this move changed while the move was
        /// waiting or retrying. The obsolete drag must stop immediately.
        case moveSuperseded(MenuBarItem)
        /// Control Center restored the autosaved slot because the source app never
        /// registered the drop. It persists for minutes then clears, so retrying only costs time.
        case dropReverted(MenuBarItem)
        /// Another move held the bar for the whole gate wait. Says nothing
        /// about the item; callers treat it as a deferral.
        case moveEngineBusy(MenuBarItem)
        /// A press outlived its deadline and was released by the guard, or
        /// the move as a whole ran past its deadline. Whatever reply came
        /// back after that describes a press that was no longer down.
        case moveTimedOut(MenuBarItem)
        /// The planned endpoints do not form a safe transport on the selected
        /// display. No synthetic press was posted.
        case unsafeMovePath(MenuBarItem)

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
            case let .missingDestinationBounds(item):
                "\(Self.self).missingDestinationBounds(item: \(item.tag))"
            case let .menuTrackingActive(item):
                "\(Self.self).menuTrackingActive(item: \(item.tag))"
            case let .ownerUnresponsive(item):
                "\(Self.self).ownerUnresponsive(item: \(item.tag))"
            case let .eventWindowMismatch(item):
                "\(Self.self).eventWindowMismatch(item: \(item.tag))"
            case let .staleDestination(item):
                "\(Self.self).staleDestination(item: \(item.tag))"
            case let .inputPauseTimedOut(item):
                "\(Self.self).inputPauseTimedOut(item: \(item.tag))"
            case let .moveSuperseded(item):
                "\(Self.self).moveSuperseded(item: \(item.tag))"
            case let .dropReverted(item):
                "\(Self.self).dropReverted(item: \(item.tag))"
            case let .moveEngineBusy(item):
                "\(Self.self).moveEngineBusy(item: \(item.tag))"
            case let .moveTimedOut(item):
                "\(Self.self).moveTimedOut(item: \(item.tag))"
            case let .unsafeMovePath(item):
                "\(Self.self).unsafeMovePath(item: \(item.tag))"
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
            case let .missingDestinationBounds(item):
                "The destination \"\(item.displayName)\" is no longer available"
            case let .menuTrackingActive(item):
                "A menu bar item's menu was open while moving \"\(item.displayName)\""
            case let .ownerUnresponsive(item):
                "\"\(item.displayName)\" is not responding and cannot be moved"
            case let .eventWindowMismatch(item):
                "A move event for \"\(item.displayName)\" was delivered to the wrong window"
            case let .staleDestination(item):
                "The menu bar rearranged while moving \"\(item.displayName)\""
            case let .inputPauseTimedOut(item):
                "Input did not pause before moving \"\(item.displayName)\""
            case let .moveSuperseded(item):
                "The requested move for \"\(item.displayName)\" is no longer current"
            case let .dropReverted(item):
                "\"\(item.displayName)\" could not be kept in its new position"
            case let .moveEngineBusy(item):
                "Another move was still in progress when \"\(item.displayName)\" was to be moved"
            case let .moveTimedOut(item):
                "Moving \"\(item.displayName)\" took too long and was stopped"
            case let .unsafeMovePath(item):
                "The path for moving \"\(item.displayName)\" is no longer safe"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .itemNotMovable:
                nil
            case let .dropReverted(item):
                // Apps without a bundle ID (e.g. a swift run build) are keyed by path,
                // and Control Center refuses their off-screen drops. Say so in the alert.
                if let app = item.sourceApplication, app.bundleIdentifier == nil {
                    "macOS put \"\(item.displayName)\" back after every attempt. Its app has no bundle identifier (it runs as a bare executable), and macOS does not keep such items in a hidden section. Build it as an app bundle to test moving it."
                } else {
                    "macOS put \"\(item.displayName)\" back after every attempt. This usually clears on its own within a few minutes; clicking the item, or quitting and reopening its app, resets it sooner. If it keeps happening, please file a bug report."
                }
            case .moveEngineBusy:
                "Wait a moment for the move in progress to finish, then try again."
            default:
                "Please try again. If the error persists, please file a bug report."
            }
        }

        /// How the failure ledger should file this error.
        var failureKind: MenuBarItemFailureLedger.FailureKind {
            indicatesUnresponsiveOwner ? .unresponsiveOwner : .other
        }

        /// Whether the owner never acknowledged our events. cannotComplete is
        /// excluded: it's the catch-all and would mark items for unrelated failures.
        var indicatesUnresponsiveOwner: Bool {
            switch self {
            case .ownerUnresponsive, .eventOperationTimeout, .itemResponseTimeout:
                true
            case .cannotComplete, .invalidEventSource, .missingMouseLocation, .eventCreationFailure,
                 .itemNotMovable, .missingItemBounds, .missingDestinationBounds, .menuTrackingActive, .eventWindowMismatch,
                 .staleDestination, .inputPauseTimedOut, .moveSuperseded, .dropReverted,
                 .moveEngineBusy, .moveTimedOut, .unsafeMovePath:
                false
            }
        }
    }

    /// Whether the user has paused input for at least `duration`.
    nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
            !MouseHelpers.isButtonPressed()
    }

    /// Returns whether physical input has paused, excluding Thaw's synthetic
    /// cursor warps and posted events from the movement/scroll timestamps.
    nonisolated func hasUserPausedPhysicalInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
            !MouseHelpers.lastMovementOccurred(within: duration, stateID: .hidSystemState) &&
            !MouseHelpers.lastScrollWheelOccurred(within: duration, stateID: .hidSystemState) &&
            !MouseHelpers.lastPointerButtonEventOccurred(within: duration, stateID: .hidSystemState)
    }

    /// Waits asynchronously for the user to pause input.
    @discardableResult
    nonisolated func waitForUserToPauseInput(
        for requiredPause: Duration? = nil,
        timeout: Duration? = nil,
        shouldContinue: (@MainActor () -> Bool)? = nil
    ) async throws -> InputPauseWaitResult {
        // A short window lets cursor warps slip between the user's own mouse moves
        // when an app churns its items (#750). Default 50 ms; override with:
        //   defaults write com.stonerl.Thaw inputPauseThresholdMs -int <milliseconds>
        let configuredPause = Duration.milliseconds(max(
            0,
            (Defaults.object(forKey: .inputPauseThresholdMs) as? Int) ?? Defaults.DefaultValue.inputPauseThresholdMs
        ))
        let pause = requiredPause ?? configuredPause
        let startedAt = ContinuousClock.now
        let waitTask = Task { () -> InputPauseWaitResult in
            while true {
                try Task.checkCancellation()
                if let shouldContinue, await !shouldContinue() {
                    return .superseded
                }
                if hasUserPausedInput(for: pause) {
                    return .paused
                }
                if let timeout, ContinuousClock.now - startedAt >= timeout {
                    return .timedOut
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        do {
            // waitTask is unstructured and doesn't inherit cancellation; without the
            // handler a cancelled caller waits forever while input stays active.
            return try await withTaskCancellationHandler {
                try await waitTask.value
            } onCancel: {
                waitTask.cancel()
            }
        } catch {
            // Only cancellation reaches here; logged so this stage is identifiable.
            MenuBarItemManager.diagLog.debug("waitForUserInputPause: wait interrupted: \(error)")
            throw EventError.cannotComplete
        }
    }

    /// Waits for a lull in user input before an automatic bulk apply starts.
    ///
    /// waitForUserToPauseInput gates each move; this gates the batch, which
    /// holds the cursor for its whole length and would otherwise fight the user (#899).
    ///
    /// Hitting the cap returns false so a later event can retry; it never
    /// overrides active input.
    ///
    /// On by default at 300 ms; disable with:
    ///   defaults write com.stonerl.Thaw bulkApplyIdleThresholdMs -int 0
    nonisolated func waitForBulkApplyIdleWindow() async -> Bool {
        let thresholdMs = (Defaults.object(forKey: .bulkApplyIdleThresholdMs) as? Int)
            ?? Defaults.DefaultValue.bulkApplyIdleThresholdMs
        let capMs = (Defaults.object(forKey: .bulkApplyIdleWaitCapMs) as? Int)
            ?? Defaults.DefaultValue.bulkApplyIdleWaitCapMs
        guard let window = MenuBarItemManager.bulkApplyIdleWindow(
            thresholdMs: thresholdMs,
            capMs: capMs
        ) else {
            return true
        }

        let start = ContinuousClock.now
        while !Task.isCancelled {
            let elapsed = ContinuousClock.now - start
            switch MenuBarItemManager.bulkApplyIdleWaitDecision(
                userHasPausedInput: hasUserPausedInput(for: window.threshold),
                elapsed: elapsed,
                cap: window.cap
            ) {
            case .ready:
                if elapsed > .zero {
                    MenuBarItemManager.diagLog.debug(
                        "Bulk apply idle gate: waited \(elapsed.milliseconds) ms for input to settle"
                    )
                }
                return true
            case .deferBatch:
                MenuBarItemManager.diagLog.debug(
                    "Bulk apply idle gate: deadline reached after \(elapsed.milliseconds) ms without a lull; deferring"
                )
                return false
            case .waiting:
                break
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return false
    }

    nonisolated func moveOperationBufferDuration() async -> Duration {
        guard let timestamp = await lastMoveOperationTimestamp else {
            return .zero
        }
        return max(.milliseconds(25) - timestamp.duration(to: .now), .zero)
    }

    /// Waits out the remaining buffer since the last move operation.
    nonisolated func waitForMoveOperationBuffer() async throws {
        let buffer = await moveOperationBufferDuration()
        if buffer > .zero {
            MenuBarItemManager.diagLog.debug("Move operation buffer: \(buffer)")
            do {
                try await Task.sleep(for: buffer)
            } catch {
                MenuBarItemManager.diagLog.debug("waitForMoveOperationBuffer: wait interrupted: \(error)")
                throw EventError.cannotComplete
            }
        }
    }

    /// Ignores cancellation, since most event operations must run to completion.
    nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    /// Returns the current bounds for the given item, with a refresh fallback if the window is missing.
    nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            return bounds
        }

        // Prefer the same windowID, then a non-clone.
        let refreshed = await MenuBarItem.getMenuBarItems(option: .onScreen)
        if let refreshedItem = refreshed.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone }) ??
            refreshed.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        {
            return refreshedItem.bounds
        }

        throw EventError.missingItemBounds(item)
    }

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

    /// Whether a cached source PID still belongs to a live process. Only
    /// ESRCH means gone; EPERM means it exists but isn't ours to signal.
    static nonisolated func previousPIDIsLive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno != ESRCH
    }

    /// The process a synthetic move event should be posted to.
    ///
    /// On macOS 26 Control Center owns every status item window, so
    /// sourcePID would target a process that doesn't own the dragged window.
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

    /// Fails an in-flight event operation early, unless something already resumed it.
    private nonisolated func resumeFailureIfNeeded(
        state: EventContinuationState,
        error: any Error
    ) {
        let continuation = currentContinuation(from: state.continuationHolder)
        if let continuation, state.didResume.tryClaimOnce() {
            continuation.resume(throwing: error)
        }
    }

    /// Whether rEvent is our own event (same eventSourceUserData) with rewritten
    /// window fields.
    ///
    /// For items parked off the left edge, WindowServer clamps the point under
    /// the Apple menu and rebinds the event there, causing a stray top-left click.
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
    /// Echoes with matching window fields pass through, so the scromble
    /// handshake is unaffected. Kill switch:
    ///   defaults write com.stonerl.Thaw discardStrayMoveEvents -bool NO
    private nonisolated var discardsStrayMoveEvents: Bool {
        (Defaults.object(forKey: .discardStrayMoveEvents) as? Bool) ?? Defaults.DefaultValue.discardStrayMoveEvents
    }

    /// Whether a synthetic event that comes back addressed to a different
    /// window than it was posted with should fail its operation immediately
    /// rather than let it run to timeout.
    ///
    /// A mismatch means the coordinates were clamped (the Apple-menu case). It's
    /// always logged; failing early is opt-in because it's unverified on hardware:
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
                // eventSourceUserData is unique per event, so a match here means
                // our event came back rebound to a different window.
                if rEvent.matches(context.event, byIntegerFields: [.eventSourceUserData]) {
                    onMismatch?(rEvent)
                }
                return rEvent
            }
            onMatch(tap)
            // No effect on a listen-only tap; kept for parity.
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

    /// Drops stray echoes of our own event before they reach the rebound window.
    ///
    /// Head-inserted and non-listen-only so it runs before the handshake taps.
    /// Those only act on matching echoes, which pass through here untouched.
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
                // innerTask often finishes before cancellation arrives, so resume directly.
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
            // Keep specific failures (e.g. window mismatch) so callers can skip retries.
            throw error
        } catch {
            // Cancellation of a superseded operation lands here.
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
    ///     The value of this parameter is multiplied by count to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling scrombleEvent.
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
