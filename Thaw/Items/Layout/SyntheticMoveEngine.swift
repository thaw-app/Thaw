//
//  SyntheticMoveEngine.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import MenuBarModel
import ThawAXCore

/// Owns synthetic Command-drag pacing and bounded AX verification; pointer takeover covers only each HID gesture.
/// Injectable clock and side effects allow testing without real input.
@MainActor
struct SyntheticMoveEngine {
    typealias MoveDestination = MenuBarItemManager.MoveDestination
    typealias EventError = MenuBarItemManager.EventError

    /// Where a drag's events are delivered.
    enum DragAddress: Equatable, CustomStringConvertible {
        /// The global HID event stream, which is every process at once.
        case hidEventTap
        /// One process, by PID. Nothing else sees the events.
        case process(pid_t)
        /// Uses the press ladder's window-addressed SkyLight records and frame for global-to-local conversion.
        /// Bypasses the HID stream and leaves the pointer in place.
        case eventRecord(pid: pid_t, window: CGWindowID, frame: CGRect)

        var description: String {
            switch self {
            case .hidEventTap: "hidEventTap"
            case let .process(pid): "pid \(pid)"
            case let .eventRecord(pid, window, _): "event record pid \(pid) window \(window)"
            }
        }
    }

    private static let diagLog = DiagLog(category: "SyntheticMoveEngine")

    let eventSemaphore: SimpleSemaphore
    let makeEventSource: @MainActor () throws -> CGEventSource
    let enumerateItems: @MainActor () async -> [MenuBarItem]

    /// Defaults to CGEvent dragging; tests inject a recorder for retries, dropX, and anchoring without real input.
    var postCommandDrag: @MainActor (CGPoint, CGPoint, CGEventSource, DragAddress, Duration) async throws -> Void =
        SyntheticMoveEngine.defaultCommandDrag

    var prepareForAttempt: @MainActor (Int) async throws -> Void = { _ in }

    /// First-attempt geometry must come from this input-free window, never before a caller's wait.
    /// Retries always enumerate fresh after restored user input.
    var initialItems: [MenuBarItem]?
    var validateHIDInput: @MainActor () throws -> Void = {}
    var cursorWatchdogTimeout: Duration = .seconds(10)

    /// Reports settled live-geometry outcomes to MovePipelineMonitor for per-channel privacy diagnostics; defaults to no-op.
    var onAttemptResult: @MainActor (DragAddress, Bool) -> Void = { _, _ in }

    /// Selects held HID gestures instead of addressed gestures; see Defaults.Key.useHeldCommandDrag.
    static var usesHeldCommandDrag: Bool {
        Defaults.bool(forKey: .useHeldCommandDrag)
    }

    /// Keep held and addressed gestures for comparison and builds with different delivery behavior.
    private static func defaultCommandDrag(
        from start: CGPoint,
        to end: CGPoint,
        source: CGEventSource,
        address: DragAddress,
        watchdogTimeout: Duration
    ) async throws {
        try Task.checkCancellation()
        if case let .eventRecord(pid, windowID, frame) = address {
            let outcome = await MenuBarItemDraggerProvider.current.commandDrag(
                ownerPID: pid,
                windowID: windowID,
                windowFrame: frame,
                from: start,
                to: end
            )
            diagLog.info("Event-record drag (window \(windowID)): \(outcome.diagnosticDescription)")
            try Task.checkCancellation()
            return
        }
        try await performCommandDrag(
            from: start, to: end, source: source, address: address, watchdogTimeout: watchdogTimeout
        )
    }

    /// Resolves MenuBarAgent's PID, or nil when it isn't running. Injected so
    /// address selection can be characterized without a live agent.
    var resolveMenuBarAgentPID: @MainActor () -> pid_t? =
        SyntheticMoveEngine.liveMenuBarAgentPID

    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        maxAttempts: Int = 2,
        experimentalSystemItemHiding: Bool = false
    ) async throws {
        guard item.isPhysicallyOrderable(experimentalSystemItemHiding: experimentalSystemItemHiding) else {
            Self.diagLog.warning("Refusing physical reorder source \(item.logString)")
            throw EventError.itemNotMovable(
                item,
                item.orderabilityRefusal(experimentalSystemItemHiding: experimentalSystemItemHiding)
            )
        }

        // Name the refused anchor, not the dragged item, in the error.
        guard destination.targetItem.isPhysicallyOrderable(
            experimentalSystemItemHiding: experimentalSystemItemHiding
        ) || destination.targetItem.tag.matchesSectionBoundaryControlItem else {
            Self.diagLog.warning("Refusing anchored target \(destination.targetItem.logString)")
            throw EventError.itemNotMovable(
                destination.targetItem,
                destination.targetItem.orderabilityRefusal(
                    experimentalSystemItemHiding: experimentalSystemItemHiding
                )
            )
        }

        let queuedAt = ContinuousClock.now
        var acquiredSemaphore = false
        do {
            try await eventSemaphore.wait(timeout: .milliseconds(3500))
            acquiredSemaphore = true
        } catch is SimpleSemaphore.TimeoutError {
            Self.diagLog.error("eventSemaphore timed out")
            throw EventError.cannotComplete
        }
        defer {
            if acquiredSemaphore {
                await eventSemaphore.signal()
            }
        }

        Self.diagLog.debug("Drag queue wait: \(ContinuousClock.now - queuedAt)")
        let source = try makeEventSource()
        // Item bounds are top-left global; NSScreen frames are bottom-left and miss a display above the main one.
        let onScreenFrames = NSScreen.allDisplayBoundsCG

        for attempt in 1 ... max(1, maxAttempts) {
            try Task.checkCancellation()
            try await prepareForAttempt(attempt)
            // The pointer is usable between attempts. Never retry against
            // geometry captured before that user-input window.
            let geometryStarted = ContinuousClock.now
            let liveItems: [MenuBarItem]
            if attempt == 1, let initialItems {
                liveItems = initialItems
                Self.diagLog.debug("Drag geometry: reused the caller's enumeration")
            } else {
                liveItems = await enumerateItems()
                Self.diagLog.debug("Drag geometry: \(ContinuousClock.now - geometryStarted)")
            }
            try Task.checkCancellation()

            if MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesDestination(
                items: liveItems,
                item: item,
                destination: destination,
                experimentalSystemItemHiding: experimentalSystemItemHiding
            ) {
                return
            }

            let itemBounds = try currentBounds(for: item, in: liveItems)
            let targetBounds = try currentBounds(for: destination.targetItem, in: liveItems)
            let start = CGPoint(x: itemBounds.midX, y: itemBounds.midY)
            let inset = Constants.MenuBarTuning.syntheticDragDropInset
            let dropX: CGFloat = switch destination {
            case .leftOfItem: targetBounds.minX - inset
            case .rightOfItem: targetBounds.maxX + inset
            }
            let end = CGPoint(x: dropX, y: targetBounds.midY)

            guard onScreenFrames.contains(where: { $0.contains(start) }),
                  onScreenFrames.contains(where: { $0.contains(end) })
            else {
                // Orderability passed, so refusal is nil; recompute it to stay accurate if the guards change.
                throw EventError.itemNotMovable(
                    item,
                    item.orderabilityRefusal(experimentalSystemItemHiding: experimentalSystemItemHiding)
                )
            }

            // Skipping rather than throwing lets the retry re-enumerate; if it
            // still points under the notch the loop ends in cannotComplete.
            if let covered = SyntheticDragNotchGuard.coveredEndpoint(start: start, end: end, notchRects: SyntheticDragNotchGuard.liveNotchRects()) {
                Self.diagLog.warning("Attempt \(attempt) refused: \(covered.point) lies under the notch \(covered.notch); \(item.logString) \(destination.logString)")
                continue
            }

            let address = dragAddress(forAttempt: attempt, item: item)
            // Use info for addressed-drag diagnostics because macOS does not persist debug messages.
            Self.diagLog.info(
                "Attempt \(attempt) via \(address): \(item.logString) \(destination.logString); " +
                    "order=\(MenuBarLayoutPlannerProvider.current.orderDescription(liveItems))"
            )
            if case .hidEventTap = address {
                try validateHIDInput()
            }
            try await postCommandDrag(start, end, source, address, cursorWatchdogTimeout)

            let verificationStarted = ContinuousClock.now
            let result = try await SyntheticMoveVerification.observe(
                budget: Constants.MenuBarTuning.syntheticDragSettleDelay,
                now: { verificationStarted.duration(to: .now) },
                sleep: { try await Task.sleep(for: $0) },
                snapshot: enumerateItems,
                isSatisfied: {
                    MenuBarLayoutPlannerProvider.current.liveOrderSatisfiesDestination(
                        items: $0,
                        item: item,
                        destination: destination,
                        experimentalSystemItemHiding: experimentalSystemItemHiding
                    )
                }
            )
            Self.diagLog.debug("Drag verification: \(ContinuousClock.now - verificationStarted)")
            onAttemptResult(address, result.satisfied)
            if result.satisfied {
                return
            }
        }

        Self.diagLog.error(
            "Exhausted \(maxAttempts) attempts moving \(item.logString) \(destination.logString)"
        )
        throw EventError.cannotComplete
    }

    static var addressesDragViaEventRecord: Bool {
        Defaults.bool(forKey: .addressMoveDragViaEventRecord)
    }

    private func dragAddress(forAttempt attempt: Int, item: MenuBarItem) -> DragAddress {
        // Address the item's own window: agent-PID point lookup cannot find a host window at its position.
        // Retry through HID if the first event-record attempt fails.
        if attempt == 1, Self.addressesDragViaEventRecord,
           item.windowID != 0,
           MenuBarItemDraggerProvider.current.isAvailable
        {
            return .eventRecord(pid: item.ownerPID, window: item.windowID, frame: item.bounds)
        }
        // The held gesture always travels the HID stream; addressing is only
        // meaningful for the original gesture.
        if Self.usesHeldCommandDrag {
            return .hidEventTap
        }
        let pid = resolveMenuBarAgentPID()
        if pid == nil, attempt == 1, Self.addressesDragToMenuBarAgent {
            Self.diagLog.warning("MenuBarAgent not running; addressing drag to the HID tap")
        }
        return Self.dragAddress(
            forAttempt: attempt,
            isEnabled: Self.addressesDragToMenuBarAgent,
            menuBarAgentPID: pid
        )
    }

    /// Pure address selection: only the first attempt targets MenuBarAgent; retries use HID if the agent ignores it.
    static nonisolated func dragAddress(
        forAttempt attempt: Int,
        isEnabled: Bool,
        menuBarAgentPID: pid_t?
    ) -> DragAddress {
        guard isEnabled, attempt == 1, let pid = menuBarAgentPID else {
            return .hidEventTap
        }
        return .process(pid)
    }

    /// See Defaults.Key.addressMoveDragToMenuBarAgent.
    static var addressesDragToMenuBarAgent: Bool {
        Defaults.bool(forKey: .addressMoveDragToMenuBarAgent)
    }

    private static func liveMenuBarAgentPID() -> pid_t? {
        AXPrimitives.menuBarAgentPID()
    }

    private func currentBounds(for item: MenuBarItem, in items: [MenuBarItem]) throws -> CGRect {
        if let match = items.first(where: { $0.windowID == item.windowID && $0.tag == item.tag }) ??
            items.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) && !$0.isSystemClone && !$0.isNativeOverflowControl }) ??
            items.first(where: { $0.tag.matchesIgnoringWindowID(item.tag) })
        {
            return match.bounds
        }
        throw EventError.missingItemBounds(item)
    }

    /// Keep holds and 800 ms travel at 60 Hz: shorter timing loses slot-crossing tracking on cross-divider moves.
    /// PRK shares the pacing and cancellation rules.
    private static func performCommandDrag(
        from start: CGPoint,
        to end: CGPoint,
        source: CGEventSource,
        address: DragAddress,
        watchdogTimeout: Duration
    ) async throws {
        var profile = usesHeldCommandDrag ? MenuBarDragGesture.held : MenuBarDragGesture(
            settleBeforePress: .milliseconds(30),
            pressHold: .milliseconds(60),
            travelDuration: .milliseconds(384),
            frameInterval: .milliseconds(16),
            holdBeforeRelease: .zero,
            maximumProgressStep: 1.0 / 20
        )
        profile.postRelease = .milliseconds(40)
        let session: SyntheticDragInputSession? = if case .hidEventTap = address {
            try SyntheticDragInputSession(
                environment: .live(source: source, watchdogTimeout: watchdogTimeout),
                watchdogTimeout: watchdogTimeout
            )
        } else {
            nil
        }
        defer { session?.finish() }
        let began = ContinuousClock.now
        let metrics = try await profile.perform(
            from: start,
            to: end,
            now: { began.duration(to: .now) },
            sleep: { try await Task.sleep(for: $0) },
            post: { phase, point in
                if let session {
                    try session.post(phase, at: point)
                } else {
                    try postMouseEvent(phase, at: point, source: source, address: address)
                }
            }
        )
        diagLog.debug(
            "Gesture via \(address): \(metrics.duration), \(metrics.motionEvents) frames, "
                + "max motion gap \(metrics.maximumMotionGap)"
        )
    }

    static func postMouseEvent(
        _ phase: MenuBarDragGesture.Phase,
        at location: CGPoint,
        source: CGEventSource,
        address: DragAddress
    ) throws {
        let type: CGEventType = switch phase {
        case .moved: .mouseMoved
        case .down: .leftMouseDown
        case .dragged: .leftMouseDragged
        case .up: .leftMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ) else { throw EventError.cannotComplete }
        event.flags = .maskCommand
        MoveInputSuppression.markSyntheticMoveEvent(event)
        switch address {
        case .hidEventTap: event.post(tap: .cghidEventTap)
        case let .process(pid): event.postToPid(pid)
        case .eventRecord: preconditionFailure("Event records use the PRK dragger")
        }
    }
}
