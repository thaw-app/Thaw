//
//  MenuBarItemManager+MoveTransaction.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa

// @preconcurrency: see the note in MenuBarItemManager.swift.
@preconcurrency import CoreGraphics

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Signals that the absolute budget shared by an entire move transaction
    /// has been exhausted.
    nonisolated struct MoveDeadlineExceeded: Error, Equatable {}

    /// One absolute budget for the whole transaction; nested waits get only what's left.
    nonisolated struct MoveTransactionBudget {
        typealias Elapsed = @Sendable () -> Duration
        typealias Sleeper = @Sendable (Duration) async throws -> Void

        let limit: Duration
        private let elapsedProvider: Elapsed
        private let sleeper: Sleeper

        init(limit: Duration) {
            let startedAt = ContinuousClock.now
            self.init(
                limit: limit,
                elapsed: { startedAt.duration(to: .now) },
                sleeper: { try await Task.sleep(for: $0) }
            )
        }

        init(
            limit: Duration,
            elapsed: @escaping Elapsed,
            sleeper: @escaping Sleeper
        ) {
            self.limit = limit
            elapsedProvider = elapsed
            self.sleeper = sleeper
        }

        var elapsed: Duration {
            elapsedProvider()
        }

        func remaining() throws -> Duration {
            let value = limit - elapsed
            guard value > .zero else {
                throw MoveDeadlineExceeded()
            }
            return value
        }

        func timeout(for requested: Duration, repeating count: Int = 1) throws -> Duration {
            let repetitions = max(1, count)
            let value = try min(requested, remaining() / repetitions)
            guard value > .zero else {
                throw MoveDeadlineExceeded()
            }
            return value
        }

        func run<Value>(
            maximum: Duration,
            repeating count: Int = 1,
            operation: (Duration) async throws -> Value
        ) async throws -> Value {
            let allowance = try timeout(for: maximum, repeating: count)
            do {
                let value = try await operation(allowance)
                _ = try remaining()
                return value
            } catch {
                if elapsed >= limit {
                    throw MoveDeadlineExceeded()
                }
                throw error
            }
        }

        func sleep(for duration: Duration) async throws {
            let available = try remaining()
            guard available >= duration else {
                try await sleeper(available)
                throw MoveDeadlineExceeded()
            }
            try await sleeper(duration)
            _ = try remaining()
        }
    }

    /// Whole transactions, not just posts, or two retry loops undo each other.
    private static let moveGate = SimpleSemaphore(value: 1)

    /// Lets a blocked-item recovery move nested inside its parent pass the gate.
    @TaskLocal private static var holdsMoveGate = false

    /// Nested recovery moves inherit their parent's absolute deadline rather
    /// than silently receiving another full transaction budget.
    @TaskLocal private static var currentMoveBudget: MoveTransactionBudget?

    private static let moveGateTimeout: Duration = .seconds(15)

    /// User activity can defer one move without retaining the app-wide move
    /// permit indefinitely.
    static nonisolated let moveInputPauseLimit: Duration = .seconds(2)

    /// Runs a caller's gate-owned completion hook before another move can enter.
    static func performMoveGateExitActions(
        didFinishWhileHoldingGate: (@MainActor () -> Void)?,
        releaseGate: () -> Void
    ) {
        didFinishWhileHoldingGate?()
        releaseGate()
    }

    /// Performs admission work before acquiring the app-wide move gate.
    /// Nested recovery moves already own the gate and enter directly.
    static func performWithMoveGate(
        timeout: Duration = moveGateTimeout,
        timeoutProvider: (@MainActor () throws -> Duration)? = nil,
        waitBeforeGate: @MainActor () async throws -> Void = { /* No admission work by default. */ },
        didFinishWhileHoldingGate: (@MainActor () -> Void)? = nil,
        operation: @MainActor () async throws -> Void
    ) async throws {
        if holdsMoveGate {
            try await operation()
            return
        }

        try await waitBeforeGate()
        try await moveGate.wait(timeout: timeoutProvider?() ?? timeout)
        defer {
            performMoveGateExitActions(
                didFinishWhileHoldingGate: didFinishWhileHoldingGate,
                releaseGate: {
                    Task.detached { await moveGate.signal() }
                }
            )
        }
        try await $holdsMoveGate.withValue(true) {
            try await operation()
        }
    }

    /// Polls until two readings agree. The confirmation bit is separate so a
    /// still-changing last sample isn't mistaken for settled.
    static nonisolated func settledReading<Value: Equatable>(
        maxPolls: Int,
        read: () async -> Value,
        wait: () async -> Void
    ) async -> (value: Value, settled: Bool) {
        var previous = await read()
        var polls = 1
        while polls < maxPolls {
            await wait()
            let current = await read()
            polls += 1
            if current == previous {
                return (current, true)
            }
            previous = current
        }
        return (previous, false)
    }

    /// Control Center animates the reflow after release, so an immediate read
    /// can reject a correct drop.
    nonisolated func waitForLayoutToSettle(
        item: MenuBarItem,
        target: MenuBarItem,
        interval: Duration = .milliseconds(25),
        maxPolls: Int = 24
    ) async {
        let outcome = await Self.settledReading(
            maxPolls: maxPolls,
            read: {
                [Bridging.getWindowBounds(for: item.windowID), Bridging.getWindowBounds(for: target.windowID)]
            },
            wait: { await self.eventSleep(for: interval) }
        )
        if !outcome.settled {
            MenuBarItemManager.diagLog.debug(
                "Layout still changing after \(maxPolls) polls while moving \(item.logString) relative to \(target.logString); verifying anyway"
            )
        }
    }

    /// Layout settling constrained by the transaction's absolute deadline.
    nonisolated func waitForLayoutToSettle(
        item: MenuBarItem,
        target: MenuBarItem,
        budget: MoveTransactionBudget,
        interval: Duration = .milliseconds(25),
        maxPolls: Int = 24
    ) async throws {
        var previous = [
            Bridging.getWindowBounds(for: item.windowID),
            Bridging.getWindowBounds(for: target.windowID),
        ]
        var polls = 1
        while polls < maxPolls {
            try await budget.sleep(for: interval)
            let current = [
                Bridging.getWindowBounds(for: item.windowID),
                Bridging.getWindowBounds(for: target.windowID),
            ]
            polls += 1
            if current == previous {
                return
            }
            previous = current
        }
        if maxPolls > 1 {
            MenuBarItemManager.diagLog.debug(
                "Layout still changing after \(maxPolls) polls while moving \(item.logString) relative to \(target.logString); verifying anyway"
            )
        }
    }

    /// Every field defaults, so callers pass only what they change.
    struct MoveOptions {
        var requiredInputPause: Duration?
        var inputPauseTimeout: Duration?
        var watchdogTimeout: Duration?
        var maxMoveAttempts: Int = 8
        var hideCursorAcrossAttempts: Bool = true
        var shouldProceed: (@MainActor () -> Bool)?
        /// Checked once the gate is held; false supersedes a move that went
        /// stale while queued.
        var shouldBegin: (@MainActor () -> Bool)?
        /// Runs while the gate is still held, after the move finished but
        /// before another move may enter.
        var didFinishWhileHoldingGate: (@MainActor () -> Void)?
        /// The user asked for this move, directly or by revealing an item.
        /// It bypasses the move circuit breaker and, on landing, clears it.
        var isUserInitiated = false
    }

    /// Shorter than the cursor watchdog and queued callers' patience.
    static nonisolated let moveDeadline: Duration = .seconds(8)

    private static func isControlCenterOwned(_ item: MenuBarItem) -> Bool {
        item.owningApplication?.bundleIdentifier == MenuBarItemTag.Namespace.controlCenter.description
    }

    /// Supplies the live ownership inputs to the pure failure-attribution rule.
    func ledgerFailureKind(for error: any Error, item: MenuBarItem) -> MenuBarItemFailureLedger.FailureKind {
        guard let error = error as? EventError else {
            return .other
        }
        return Self.ledgerFailureKind(
            for: error,
            ownerIsControlCenter: Self.isControlCenterOwned(item),
            hasProvisionalIdentity: item.hasProvisionalIdentity
        )
    }

    private func recordLanding(of item: MenuBarItem) {
        failureLedger.recordSuccess(for: item)
        clearRefusedMove(of: item)
    }

    private func logStop(
        _ reason: MovePolicy.StopReason,
        attempt: Int,
        item: MenuBarItem,
        destination: MoveDestination,
        state: MovePolicy.State,
        maxAttempts: Int,
        error: (any Error)?
    ) {
        switch reason {
        case .refusedByMacOS:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(item.logString) returned to its starting origin after consecutive releases; abandoning the move"
            )
        case .targetMoved:
            let planned = state.plannedTargetMinX.map { String(format: "%.0f", $0) } ?? "?"
            let current = state.latestTargetMinX.map { String(format: "%.0f", $0) } ?? "?"
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) moved from minX=\(planned) to minX=\(current); abandoning the stale move"
            )
        case .targetRetreating:
            let history = state.targetMinXHistory.map { String(format: "%.0f", $0) }.joined(separator: " → ")
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) retreated on every recent attempt (\(history)); abandoning the move"
            )
        case .ownerUnresponsive:
            MenuBarItemManager.diagLog.warning("Attempt \(attempt): \(item.logString) owner is unresponsive")
        case .ownerAlwaysSilent:
            MenuBarItemManager.diagLog.warning("Attempt \(attempt): \(item.logString) repeated its standing silent-owner failure")
        case .ownerSilent, .other:
            MenuBarItemManager.diagLog.debug(
                "Attempt \(attempt) failed: \(error.map { "\($0)" } ?? "unknown error")"
            )
        case .itemGone:
            MenuBarItemManager.diagLog.warning("Attempt \(attempt): \(item.logString) no longer reports bounds")
        case .destinationGone:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) no longer reports bounds"
            )
        case .staleDestination:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(destination.targetItem.logString) no longer matches the move plan"
            )
        case .superseded:
            MenuBarItemManager.diagLog.debug("move: superseded during attempt \(attempt) for \(item.logString)")
        case .overran:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): the press on \(item.logString) outlived its deadline"
            )
        case .unsafePath:
            MenuBarItemManager.diagLog.warning(
                "Attempt \(attempt): \(item.logString) has no safe transport to the selected destination"
            )
        case .budgetExhausted:
            MenuBarItemManager.diagLog.error(
                "move: all \(maxAttempts) attempt(s) exhausted without verifying \(item.logString) reached \(destination.logString)"
            )
        }
    }

    private func isAtDestination(
        _ item: MenuBarItem,
        for destination: MoveDestination,
        on displayID: CGDirectDisplayID
    ) async -> Bool {
        await (try? itemHasCorrectPosition(item: item, for: destination, on: displayID)) ?? false
    }

    /// Rechecks plausible landings against a settled bar, then records and
    /// throws the policy's precise terminal verdict.
    private func concludeFailedMove(
        reason: MovePolicy.StopReason,
        item: MenuBarItem,
        destination: MoveDestination,
        on displayID: CGDirectDisplayID,
        attempts: Int,
        budget: MoveTransactionBudget,
        lastError: (any Error)?
    ) async throws {
        if reason.deservesFinalLandingCheck, budget.elapsed < budget.limit {
            do {
                try await waitForLayoutToSettle(
                    item: item,
                    target: destination.targetItem,
                    budget: budget
                )
            } catch is MoveDeadlineExceeded {
                throw EventError.moveTimedOut(item)
            }
            if await isAtDestination(item, for: destination, on: displayID) {
                MenuBarItemManager.diagLog.info(
                    "Move landed: \(item.logString) after \(attempts) attempt(s); confirmed after stopping for \(reason.logString)"
                )
                recordLanding(of: item)
                return
            }
        }
        if reason == .budgetExhausted {
            await validateItemPositionAfterMove(item: item, destination: destination, on: displayID)
        }
        if reason == .refusedByMacOS {
            noteRefusedMove(of: item)
        }
        if reason.isFiledAgainstOwner, let lastError {
            failureLedger.recordFailure(for: item, kind: ledgerFailureKind(for: lastError, item: item))
        }
        MenuBarItemManager.diagLog.info(
            "Move verdict: \(reason.logString) for \(item.logString) after \(attempts) attempt(s) in \(Int(budget.elapsed.milliseconds)) ms"
        )
        throw Self.moveError(
            for: reason,
            item: item,
            destinationItem: destination.targetItem,
            lastError: lastError
        )
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameter options: The move tunables; every field defaults.
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        on displayID: CGDirectDisplayID? = nil,
        skipInputPause: Bool = false,
        options: MoveOptions = .init()
    ) async throws {
        let budget = Self.currentMoveBudget ?? MoveTransactionBudget(limit: Self.moveDeadline)

        // Nested recovery moves already own the gate.
        if !Self.holdsMoveGate {
            // Runaway guard. Superseded, not failed: the item did nothing
            // wrong, so no caller files the refusal against it.
            if moveCircuitBreaker.isOpen {
                if !options.isUserInitiated {
                    MenuBarItemManager.diagLog.debug(
                        "Move circuit breaker open; skipping automatic move of \(item.logString)"
                    )
                    throw EventError.moveSuperseded(item)
                }
                MenuBarItemManager.diagLog.info(
                    "Move circuit breaker open; allowing the user's move of \(item.logString)"
                )
            }
            do {
                try await Self.performWithMoveGate(
                    timeoutProvider: {
                        try budget.timeout(for: Self.moveGateTimeout)
                    },
                    waitBeforeGate: {
                        guard !skipInputPause else {
                            return
                        }
                        let allowance = try budget.timeout(for: Self.moveInputPauseLimit)
                        let waitTask = Task(timeout: allowance) {
                            try await self.waitForUserToPauseInput(
                                for: options.requiredInputPause,
                                timeout: options.inputPauseTimeout,
                                shouldContinue: options.shouldProceed
                            )
                        }
                        do {
                            switch try await waitTask.value {
                            case .paused:
                                break
                            case .timedOut:
                                throw EventError.inputPauseTimedOut(item)
                            case .superseded:
                                throw EventError.moveSuperseded(item)
                            }
                        } catch let error as EventError {
                            throw error
                        } catch is TaskTimeoutError {
                            // The budget ran out before the pause wait's own
                            // timeout; still an input-pause deferral.
                            MenuBarItemManager.diagLog.debug(
                                "move: input did not pause within \(allowance) for \(item.logString)"
                            )
                            throw EventError.inputPauseTimedOut(item)
                        } catch {
                            _ = try budget.remaining()
                            MenuBarItemManager.diagLog.debug(
                                "move: input did not pause within \(allowance) for \(item.logString)"
                            )
                            throw EventError.cannotComplete
                        }
                    },
                    didFinishWhileHoldingGate: options.didFinishWhileHoldingGate,
                    operation: {
                        // Input can resume while queued; recheck without waiting.
                        if !skipInputPause {
                            let pauseMs = max(
                                0,
                                (Defaults.object(forKey: .inputPauseThresholdMs) as? Int)
                                    ?? Defaults.DefaultValue.inputPauseThresholdMs
                            )
                            guard self.hasUserPausedInput(for: .milliseconds(pauseMs)) else {
                                throw EventError.cannotComplete
                            }
                        }
                        var nestedOptions = options
                        nestedOptions.didFinishWhileHoldingGate = nil
                        _ = try budget.remaining()
                        try await Self.$currentMoveBudget.withValue(budget) {
                            try await self.move(
                                item: item,
                                to: destination,
                                on: displayID,
                                skipInputPause: true,
                                options: nestedOptions
                            )
                        }
                    }
                )
            } catch is MoveDeadlineExceeded {
                throw EventError.moveTimedOut(item)
            } catch is SimpleSemaphore.TimeoutError {
                if budget.elapsed >= budget.limit {
                    throw EventError.moveTimedOut(item)
                }
                MenuBarItemManager.diagLog.error("move: another move held the bar until admission timed out for \(item.logString)")
                throw EventError.moveEngineBusy(item)
            } catch {
                if budget.elapsed >= budget.limit {
                    throw EventError.moveTimedOut(item)
                }
                throw error
            }
            if options.isUserInitiated {
                moveCircuitBreaker.noteUserOverride()
            }
            return
        }

        // Once, after taking the gate, so the move's own updates don't read as supersession.
        guard options.shouldBegin?() ?? true else {
            throw EventError.moveSuperseded(item)
        }

        // Backstop: a dragged clone displaces real items. It vanishes on its own,
        // so a no-op is correct.
        guard !item.isSystemClone else {
            MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - system status item clone")
            return
        }
        guard item.isMovableAddressingWindowOwner else {
            // Tells a macOS prohibition apart from an identity-resolution failure (#905).
            MenuBarItemManager.diagLog.warning(
                "move: refusing \(item.logString): \(item.immovabilityReason?.logDescription ?? "isMovable false with no named gate"); uniqueIdentifier=\(item.uniqueIdentifier), sourcePID=\(item.sourcePID.map(String.init) ?? "nil")"
            )
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            MenuBarItemManager.diagLog.error("move: no appState; cannot move \(item.logString)")
            throw EventError.cannotComplete
        }
        guard options.shouldProceed?() ?? true else {
            throw EventError.moveSuperseded(item)
        }

        // A synthetic Cmd-drag tears down an open menu. Wait briefly, then give up.
        var menuWaitAttempts = 0
        while await isAnyMenuBarItemMenuOpen() {
            guard options.shouldProceed?() ?? true else {
                throw EventError.moveSuperseded(item)
            }
            menuWaitAttempts += 1
            if menuWaitAttempts > 20 { // ~5s at 250ms steps
                MenuBarItemManager.diagLog.warning("move: menu still open after wait; deferring move of \(item.logString)")
                throw EventError.menuTrackingActive(item)
            }
            try await budget.sleep(for: .milliseconds(250))
        }

        // Right-of moves are the rescue path; anything else could drag a stuck
        // item somewhere unknown.
        if await isItemBlocked(item) {
            guard case .rightOfItem = destination else {
                MenuBarItemManager.diagLog.warning("Skipping move for \(item.logString) - item is blocked (x=-1)")
                throw EventError.cannotComplete
            }
            MenuBarItemManager.diagLog.debug("Proceeding with move of blocked \(item.logString); recovery to visible")
        }

        let resolvedDisplayID: CGDirectDisplayID = if let displayID {
            displayID
        } else if let window = appState.hidEventManager.bestScreen(appState: appState) {
            window.displayID
        } else {
            Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID()
        }

        // The plan may have waited in the queue. Require the same window, owner,
        // tag, and source; a same-tag replacement needs a new plan.
        _ = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: resolvedDisplayID
        )
        guard options.shouldProceed?() ?? true else {
            throw EventError.moveSuperseded(item)
        }
        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let initialBuffer = await moveOperationBufferDuration()
        if initialBuffer > .zero {
            try await budget.sleep(for: initialBuffer)
        }

        // The buffer is an await, so check the endpoints again.
        let bufferedEndpoints = try await resolveCurrentMoveEndpoints(
            source: item,
            destination: destination.targetItem,
            on: resolvedDisplayID,
            requiresFullSnapshot: true
        )

        MenuBarItemManager.diagLog.info(
            """
            Moving \(item.logString) to \
            \(destination.logString) on display \(resolvedDisplayID)
            """
        )

        guard !Self.endpointsHaveCorrectPosition(bufferedEndpoints, for: destination) else {
            MenuBarItemManager.diagLog.debug("Item has correct position, cancelling move")
            recordLanding(of: item)
            return
        }

        if !options.isUserInitiated {
            moveCircuitBreaker.note(.move(identifier: item.uniqueIdentifier))
        }

        // Warp back once after all attempts, not per attempt, or the cursor oscillates.
        let mouseLocation = options.hideCursorAcrossAttempts ? try getMouseLocation() : nil
        let cursorOwnershipStartedAt = ContinuousClock.now
        // The default 1 s watchdog is far too short; a premature fire flashes the
        // cursor mid-display. See cursorHideWatchdogTimeout.
        if options.hideCursorAcrossAttempts {
            let cursorWatchdog = try min(
                options.watchdogTimeout ?? Self.cursorHideWatchdogTimeout(
                    maxAttempts: max(1, options.maxMoveAttempts)
                ),
                budget.remaining()
            )
            MouseHelpers.hideCursor(watchdogTimeout: cursorWatchdog)
        }
        defer {
            if let mouseLocation {
                let physicalInputOccurred = MouseHelpers.physicalPointerInputOccurred(
                    since: cursorOwnershipStartedAt
                )
                if MouseHelpers.shouldRestoreSavedCursorPosition(
                    physicalPointerInputOccurred: physicalInputOccurred
                ) {
                    MouseHelpers.restoreCursorPosition(to: mouseLocation)
                } else {
                    MenuBarItemManager.diagLog.debug(
                        "move: preserving physical pointer movement made during the transaction"
                    )
                }
                MouseHelpers.showCursor()
            }
        }

        var policyState = MovePolicy.State(plannedTargetMinX: bufferedEndpoints.target.bounds.minX)
        let configuration = MovePolicy.Configuration(
            maxAttempts: max(1, options.maxMoveAttempts),
            displayWidth: CGDisplayBounds(resolvedDisplayID).width,
            itemIsControlItem: item.isControlItem,
            ownerHasSilentRecord: failureLedger.isUnresponsive(item)
        )
        var lastError: (any Error)?
        var stopReason: MovePolicy.StopReason?

        attemptLoop: while stopReason == nil {
            let n = policyState.attempts + 1
            guard !Task.isCancelled else {
                MenuBarItemManager.diagLog.debug("move: cancelled before attempt \(n) for \(item.logString)")
                throw EventError.cannotComplete
            }
            guard options.shouldProceed?() ?? true else {
                MenuBarItemManager.diagLog.debug("move: superseded before attempt \(n) for \(item.logString)")
                throw EventError.moveSuperseded(item)
            }
            guard MovePolicy.mayStartAnotherAttempt(elapsed: budget.elapsed, deadline: budget.limit) else {
                MenuBarItemManager.diagLog.warning(
                    "move: \(item.logString) has been moving for \(Int(budget.elapsed.milliseconds)) ms; not starting attempt \(n)"
                )
                stopReason = .overran
                break attemptLoop
            }

            let observation: MovePolicy.Observation
            var attemptStrategy: MoveStrategy?
            lastError = nil
            do {
                if try await itemHasCorrectPosition(item: item, for: destination, on: resolvedDisplayID),
                   MovePolicy.trustsPositionMatch(
                       attempt: n,
                       anyEventsSucceeded: policyState.anyEventsSucceeded,
                       itemIsControlItem: item.isControlItem
                   )
                {
                    MenuBarItemManager.diagLog.debug("Item has correct position, finished with move")
                    recordLanding(of: item)
                    return
                }

                let outcome = try await postMoveEvents(
                    item: item,
                    destination: destination,
                    on: resolvedDisplayID,
                    budget: budget,
                    warpCursorAfter: false,
                    preferSourceAnchoredTeleport: policyState.revertedRun > 0
                )
                attemptStrategy = outcome.strategy
                try await waitForLayoutToSettle(
                    item: item,
                    target: destination.targetItem,
                    budget: budget
                )
                let settledEndpoints = try await resolveCurrentMoveEndpoints(
                    source: item,
                    destination: destination.targetItem,
                    on: resolvedDisplayID,
                    requiresFullSnapshot: true
                )
                let landed = Self.endpointsHaveCorrectPosition(settledEndpoints, for: destination)
                updateMoveOperationTimeout(
                    Self.nextMoveOperationTimeout(
                        after: outcome.timeout,
                        outcome: landed ? .landed : .displacedWithoutLanding
                    ),
                    for: item
                )
                observation = landed
                    ? .landed
                    : .displaced(
                        revertedToStart: outcome.revertedToStart,
                        targetMinX: settledEndpoints.target.bounds.minX
                    )
            } catch is MoveDeadlineExceeded {
                lastError = EventError.moveTimedOut(item)
                observation = .failed(.overran)
            } catch let error as EventError {
                lastError = error
                observation = .failed(MovePolicy.attemptFailure(for: error))
            } catch {
                lastError = error
                observation = .failed(.other)
            }

            switch MovePolicy.decide(
                after: observation,
                state: &policyState,
                configuration: configuration
            ) {
            case .succeed:
                MenuBarItemManager.diagLog.info(
                    "Move landed: \(item.logString) after \(n) attempt(s)\(attemptStrategy.map { " via \($0)" } ?? "")"
                )
                recordLanding(of: item)
                await validateItemPositionAfterMove(
                    item: item,
                    destination: destination,
                    on: resolvedDisplayID
                )
                return
            case .retry:
                if case .failed = observation {
                    MenuBarItemManager.diagLog.debug(
                        "Attempt \(n) failed: \(lastError.map { "\($0)" } ?? "unknown error")"
                    )
                } else {
                    MenuBarItemManager.diagLog.debug(
                        "Attempt \(n) events succeeded but item not at destination, retrying"
                    )
                }
                let retryBuffer = await moveOperationBufferDuration()
                if retryBuffer > .zero {
                    try await budget.sleep(for: retryBuffer)
                }
            case let .stop(reason):
                stopReason = reason
                logStop(
                    reason,
                    attempt: n,
                    item: item,
                    destination: destination,
                    state: policyState,
                    maxAttempts: configuration.maxAttempts,
                    error: lastError
                )
            }
        }

        if !options.isUserInitiated {
            moveCircuitBreaker.note(.failedMove)
        }
        try await concludeFailedMove(
            reason: stopReason ?? .other,
            item: item,
            destination: destination,
            on: resolvedDisplayID,
            attempts: policyState.attempts,
            budget: budget,
            lastError: lastError
        )
    }
}
