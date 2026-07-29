//
//  EventTap.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import os.lock
import Synchronization

/// An object that receives events from a defined point in
/// the event stream.
///
/// Invariant: `callback`, `runLoop`, and the `creation*` parameters are `let`s
/// set once at init and never mutated. The only mutable state (`machPort`,
/// `source`, `isInvalidated`) lives in `state`, an `OSAllocatedUnfairLock`, and
/// is only ever read or written under that lock — including from the
/// `sharedCallback` C callback (which runs on `runLoop`, always the main run
/// loop) and from `enable()`/`disable()` calls made off the main actor.
final nonisolated class EventTap: @unchecked Sendable {
    /// Pool to limit concurrent EventTaps and prevent Mach port leaks
    private static let activeTaps = Mutex<Set<ObjectIdentifier>>([])
    private static let maxConcurrentTaps = 10

    /// Request access to create a new tap
    private static func requestTapCreation() -> Bool {
        activeTaps.withLock { $0.count < maxConcurrentTaps }
    }

    /// Register a new tap
    private static func registerTap(_ tap: EventTap) {
        activeTaps.withLock { _ = $0.insert(ObjectIdentifier(tap)) }
    }

    /// Unregister a tap
    private static func unregisterTap(_ tap: EventTap) {
        activeTaps.withLock { _ = $0.remove(ObjectIdentifier(tap)) }
    }

    /// Constants that specify the possible insertion points
    /// for event taps.
    enum Location {
        /// The point where HID system events enter the window
        /// server.
        case hidEventTap

        /// The point where HID system and remote control events
        /// enter a login session.
        case sessionEventTap

        /// The point for session events that have been annotated
        /// to flow to an application.
        case annotatedSessionEventTap

        /// The point where events are delivered to the process
        /// with the specified identifier.
        case pid(pid_t)

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .hidEventTap: "HID event tap"
            case .sessionEventTap: "session event tap"
            case .annotatedSessionEventTap: "annotated session event tap"
            case let .pid(pid): "PID \(pid)"
            }
        }
    }

    /// Shared logger for event taps.
    private nonisolated static let diagLog = DiagLog(category: "EventTap")

    /// Shared callback for all event taps.
    private nonisolated static let sharedCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let unretained: EventTap = Unmanaged.fromOpaque(refcon).takeUnretainedValue()
        return withExtendedLifetime(unretained) { tap in
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
                diagLog.warning("Event tap \"\(tap.label)\" was disabled by \(reason), re-enabling")
                tap.enable()
                return nil
            }
            guard tap.isEnabled else {
                return Unmanaged.passUnretained(event)
            }
            guard let eventFromCallback = tap.callback(tap, event) else {
                return nil
            }
            return Unmanaged.passUnretained(eventFromCallback)
        }
    }

    private struct TapState {
        var machPort: CFMachPort?
        var source: CFRunLoopSource?
        var isInvalidated = false
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: TapState())
    private let runLoop: CFRunLoop
    private let callback: (EventTap, CGEvent) -> CGEvent?

    /// Stored creation parameters for tap recreation.
    private let creationTypes: [CGEventType]
    private let creationLocation: Location
    private let creationPlacement: CGEventTapPlacement
    private let creationOption: CGEventTapOptions

    /// A string label that identifies the tap.
    let label: String

    /// A Boolean value that indicates whether the tap is actively
    /// listening for events.
    var isEnabled: Bool {
        state.withLock { state in
            guard let machPort = state.machPort else { return false }
            return CGEvent.tapIsEnabled(tap: machPort)
        }
    }

    /// A Boolean value that indicates whether the tap is valid and
    /// able to receive events.
    var isValid: Bool {
        state.withLock { state in
            guard let machPort = state.machPort else { return false }
            return CFMachPortIsValid(machPort)
        }
    }

    /// Creates a new event tap for the specified event types.
    ///
    /// If the tap is an active filter, the callback can return
    /// one of the following:
    ///
    ///   * The (possibly modified) received event to pass back to
    ///     the event stream.
    ///   * A new event to pass to the event stream in place of the
    ///     received event.
    ///   * `nil` to remove the received event from the event stream.
    ///
    /// If the tap is a passive listener, the callback's return value
    /// does not affect the event stream.
    ///
    /// - Parameters:
    ///   - label: A string label that identifies the tap in logging
    ///     and debugging contexts.
    ///   - types: The event types monitored by the tap.
    ///   - location: The point in the event stream to insert the tap.
    ///   - placement: The tap's placement, relative to existing taps
    ///     at `location`.
    ///   - option: An option that specifies whether the tap is an
    ///     active filter or a passive listener.
    ///   - callback: A closure the tap calls to handle received events.
    init(
        label: String = #function,
        types: [CGEventType],
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.label = label
        self.callback = callback
        self.runLoop = CFRunLoopGetMain()
        self.creationTypes = types
        self.creationLocation = location
        self.creationPlacement = placement
        self.creationOption = option

        // Check if we can create a new tap to prevent Mach port leaks
        guard Self.requestTapCreation() else {
            EventTap.diagLog.warning("Too many active EventTaps, rejecting creation of \(label)")
            return
        }

        let retained = Unmanaged.passRetained(self)
        guard
            let machPort = EventTap.createMachPort(
                mask: types.reduce(0) { $0 | (1 << $1.rawValue) },
                location: location,
                place: placement,
                options: option,
                userInfo: retained.toOpaque()
            ),
            let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        else {
            retained.release()
            EventTap.diagLog.error("Error creating event tap \"\(label)\"")
            return
        }

        // Register this tap
        Self.registerTap(self)

        // `withLockUnchecked` (not `withLock`) because `machPort`/`source`
        // are `CFMachPort`/`CFRunLoopSource`, non-`Sendable` types that
        // `withLock`'s `@Sendable` closure can't capture. Safe here: this is
        // the only reference to these locals, handed off to `state` under
        // the lock and never touched outside it again.
        state.withLockUnchecked { state in
            state.machPort = machPort
            state.source = source
        }
    }

    /// Creates a new event tap for the specified event type.
    ///
    /// If the tap is an active filter, the callback can return
    /// one of the following:
    ///
    ///   * The (possibly modified) received event to pass back to
    ///     the event stream.
    ///   * A new event to pass to the event stream in place of the
    ///     received event.
    ///   * `nil` to remove the received event from the event stream.
    ///
    /// If the tap is a passive listener, the callback's return value
    /// does not affect the event stream.
    ///
    /// - Parameters:
    ///   - label: A string label that identifies the tap in logging
    ///     and debugging contexts.
    ///   - type: The event type monitored by the tap.
    ///   - location: The point in the event stream to insert the tap.
    ///   - placement: The tap's placement, relative to existing taps
    ///     at `location`.
    ///   - option: An option that specifies whether the tap is an
    ///     active filter or a passive listener.
    ///   - callback: A closure the tap calls to handle received events.
    convenience init(
        label: String = #function,
        type: CGEventType,
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.init(
            label: label,
            types: [type],
            location: location,
            placement: placement,
            option: option,
            callback: callback
        )
    }

    deinit {
        invalidate()
    }

    /// Checks whether the tap is still valid and attempts to recreate
    /// it if the Mach port has been invalidated. Returns `true` if the
    /// tap is valid after this call (either already valid or successfully
    /// recreated).
    @discardableResult
    func ensureValid() -> Bool {
        if isValid {
            return true
        }
        let tapLabel = self.label
        let (hasMachPort, invalidated) = state.withLock { state in
            (state.machPort != nil, state.isInvalidated)
        }
        if !hasMachPort, !invalidated {
            // Tap was never successfully created.
            Self.diagLog.warning("Event tap \"\(tapLabel)\" has no Mach port, attempting creation")
            return recreate()
        }
        if invalidated {
            Self.diagLog.warning("Event tap \"\(tapLabel)\" was invalidated, cannot recreate")
            return false
        }
        Self.diagLog.warning("Event tap \"\(tapLabel)\" Mach port is invalid, attempting recreation")
        return recreate()
    }

    /// Tears down the current tap and creates a new one using the
    /// original parameters. Returns `true` on success.
    private func recreate() -> Bool {
        let tapLabel = self.label
        // Clean up the old tap without setting isInvalidated (we want to reuse this instance).
        Self.unregisterTap(self)
        // Record whether the mach port cleanup requires balancing the retain
        // taken at creation, but perform the release only after the lock
        // scope exits (see the matching comment in `invalidate()`).
        let needsRelease = state.withLock { state -> Bool in
            if let source = state.source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
                state.source = nil
            }
            if let machPort = state.machPort {
                CGEvent.tapEnable(tap: machPort, enable: false)
                CFMachPortInvalidate(machPort)
                state.machPort = nil
                return true
            }
            return false
        }
        if needsRelease {
            Unmanaged.passUnretained(self).release()
        }

        guard Self.requestTapCreation() else {
            Self.diagLog.warning("Too many active EventTaps, cannot recreate \"\(tapLabel)\"")
            return false
        }

        let retained = Unmanaged.passRetained(self)
        guard
            let newMachPort = EventTap.createMachPort(
                mask: creationTypes.reduce(0) { $0 | (1 << $1.rawValue) },
                location: creationLocation,
                place: creationPlacement,
                options: creationOption,
                userInfo: retained.toOpaque()
            ),
            let newSource = CFMachPortCreateRunLoopSource(nil, newMachPort, 0)
        else {
            retained.release()
            Self.diagLog.error("Failed to recreate event tap \"\(tapLabel)\"")
            return false
        }

        Self.registerTap(self)
        // `withLockUnchecked`: see the comment at the other `machPort`/
        // `source` assignment above — same non-`Sendable` capture issue.
        state.withLockUnchecked { state in
            state.machPort = newMachPort
            state.source = newSource
        }
        Self.diagLog.info("Successfully recreated event tap \"\(tapLabel)\"")
        return true
    }

    /// Invalidates the event tap and releases its resources.
    func invalidate() {
        let alreadyInvalidated = state.withLock { state -> Bool in
            if state.isInvalidated {
                return true
            }
            state.isInvalidated = true
            return false
        }
        guard !alreadyInvalidated else {
            return
        }
        Self.unregisterTap(self)
        // Record whether the mach port cleanup requires balancing the retain
        // taken at creation, but perform the release only after the lock
        // scope exits: releasing `self` inside the critical section could
        // trigger `deinit` (and thus re-entrant locking) while the lock is
        // still held.
        let needsRelease = state.withLock { state -> Bool in
            if let source = state.source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
                state.source = nil
            }
            if let machPort = state.machPort {
                CGEvent.tapEnable(tap: machPort, enable: false)
                CFMachPortInvalidate(machPort)
                state.machPort = nil
                return true
            }
            return false
        }
        if needsRelease {
            Unmanaged.passUnretained(self).release()
        }
    }

    /// Creates an event tap mach port.
    private static func createMachPort(
        mask: CGEventMask,
        location: Location,
        place: CGEventTapPlacement,
        options: CGEventTapOptions,
        userInfo: UnsafeMutableRawPointer
    ) -> CFMachPort? {
        func createMachPort(at tapLocation: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: tapLocation,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: sharedCallback,
                userInfo: userInfo
            )
        }

        func createMachPort(for pid: pid_t) -> CFMachPort? {
            CGEvent.tapCreateForPid(
                pid: pid,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: sharedCallback,
                userInfo: userInfo
            )
        }

        switch location {
        case .hidEventTap:
            return createMachPort(at: .cghidEventTap)
        case .sessionEventTap:
            return createMachPort(at: .cgSessionEventTap)
        case .annotatedSessionEventTap:
            return createMachPort(at: .cgAnnotatedSessionEventTap)
        case let .pid(pid):
            return createMachPort(for: pid)
        }
    }

    /// Enables the tap.
    func enable() {
        state.withLock { state in
            guard let source = state.source, let machPort = state.machPort else { return }
            CGEvent.tapEnable(tap: machPort, enable: true)
            CFRunLoopAddSource(runLoop, source, .commonModes)
        }
    }

    /// Disables the tap.
    func disable() {
        state.withLock { state in
            guard let source = state.source, let machPort = state.machPort else { return }
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: machPort, enable: false)
        }
    }
}
