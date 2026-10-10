//
//  EventTap.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import os.lock
import Synchronization

/// A splice into the system event stream that hands every matching event
/// to a Swift closure before the event continues on its way.
///
/// Invariant: callback, runLoop, and the creation* parameters are lets
/// set once at init and never mutated. The only mutable state (machPort,
/// source, isInvalidated) lives in state, an OSAllocatedUnfairLock, and
/// is only ever read or written under that lock, including from the
/// sharedCallback C callback (which runs on runLoop, always the main run
/// loop) and from enable()/disable() calls made off the main actor.
final nonisolated class EventTap: @unchecked Sendable {
    /// Pool to limit concurrent EventTaps and prevent Mach port leaks
    private static let activeTaps = Mutex<Set<ObjectIdentifier>>([])
    private static let maxConcurrentTaps = 10

    private static func requestTapCreation() -> Bool {
        activeTaps.withLock { $0.count < maxConcurrentTaps }
    }

    private static func registerTap(_ tap: EventTap) {
        activeTaps.withLock { _ = $0.insert(ObjectIdentifier(tap)) }
    }

    private static func unregisterTap(_ tap: EventTap) {
        activeTaps.withLock { _ = $0.remove(ObjectIdentifier(tap)) }
    }

    /// The stage of the event stream that a tap listens at.
    enum Location {
        /// Where the window server first picks up hardware input.
        case hidEventTap

        /// Where hardware and remote control input reaches a login session.
        case sessionEventTap

        /// Where session events already addressed to an app travel.
        case annotatedSessionEventTap

        /// Where events are handed to a single process.
        case pid(pid_t)

        /// A short description of the location, for log messages.
        var logString: String {
            switch self {
            case .hidEventTap: "HID tap"
            case .sessionEventTap: "session tap"
            case .annotatedSessionEventTap: "annotated session tap"
            case let .pid(pid): "PID \(pid)"
            }
        }

        /// The system-wide tap location this case names, or nil when the tap
        /// targets one process instead of a shared stage of the stream.
        private var systemLocation: CGEventTapLocation? {
            switch self {
            case .hidEventTap: .cghidEventTap
            case .sessionEventTap: .cgSessionEventTap
            case .annotatedSessionEventTap: .cgAnnotatedSessionEventTap
            case .pid: nil
            }
        }

        /// Asks Core Graphics for a Mach port that delivers the events picked
        /// out by mask at this location, or nil if it refuses.
        ///
        /// userInfo is handed back verbatim to EventTap.sharedCallback.
        fileprivate func openMachPort(
            mask: CGEventMask,
            place: CGEventTapPlacement,
            options: CGEventTapOptions,
            userInfo: UnsafeMutableRawPointer
        ) -> CFMachPort? {
            guard let systemLocation else {
                guard case let .pid(pid) = self else {
                    return nil
                }
                return CGEvent.tapCreateForPid(
                    pid: pid,
                    place: place,
                    options: options,
                    eventsOfInterest: mask,
                    callback: EventTap.sharedCallback,
                    userInfo: userInfo
                )
            }
            return CGEvent.tapCreate(
                tap: systemLocation,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: EventTap.sharedCallback,
                userInfo: userInfo
            )
        }
    }

    /// The outcome of trying to open a Mach port for a tap.
    private enum PortResult {
        /// The port and its run loop source are live and recorded in state.
        case opened

        /// The process-wide tap budget is used up; nothing was created.
        case poolExhausted

        /// Core Graphics turned the request down.
        case refused
    }

    /// The log destination shared by every tap.
    private static let diagLog = DiagLog(category: "EventTap")

    /// Pseudo event types the window server sends when it shuts a tap down,
    /// rather than real events travelling through the stream.
    private static let disableNotices: Set<CGEventType> = [
        .tapDisabledByTimeout,
        .tapDisabledByUserInput,
    ]

    /// The single C entry point that all taps are created with.
    ///
    /// The tap reaches Core Graphics as an unretained opaque pointer, so the
    /// first thing this does is turn that pointer back into an EventTap and
    /// pin it for the length of the call.
    private static let sharedCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            // Without a back pointer there is nobody to consult; wave it through.
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
        return withExtendedLifetime(tap) {
            tap.process(event, of: type)
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

    /// The bit mask that selects the tap's event types for Core Graphics.
    private var creationMask: CGEventMask {
        creationTypes.reduce(into: CGEventMask(0)) { mask, type in
            mask |= 1 << type.rawValue
        }
    }

    /// Names this tap in log messages.
    let label: String

    /// Whether the tap is switched on and currently pulling events off
    /// the stream.
    var isEnabled: Bool {
        state.withLock { state in
            guard let machPort = state.machPort else { return false }
            return CGEvent.tapIsEnabled(tap: machPort)
        }
    }

    /// Whether the tap's Mach port is still live, so events can still
    /// reach it.
    var isValid: Bool {
        state.withLock { state in
            guard let machPort = state.machPort else { return false }
            return CFMachPortIsValid(machPort)
        }
    }

    /// Splices a tap into the event stream for a set of event types.
    ///
    /// An active filter decides what the rest of the system sees: return the
    /// received event to let it continue, return a different event to swap it
    /// out, or return nil to drop it. A passive listener only observes,
    /// whatever its callback returns is ignored.
    ///
    /// The tap starts out inert; call enable() to begin receiving events.
    ///
    /// - Parameters:
    ///   - label: A name for the tap, used in logs and while debugging.
    ///   - types: The kinds of event the tap wants to see.
    ///   - location: The stage of the event stream to splice into.
    ///   - placement: Where the tap sits among the taps already installed
    ///     at location.
    ///   - option: Whether the tap may alter the stream or merely watch it.
    ///   - callback: The closure invoked for each event the tap receives.
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

        switch openPort() {
        case .opened:
            break
        case .poolExhausted:
            EventTap.diagLog.warning("Too many active EventTaps, rejecting creation of \(label)")
        case .refused:
            EventTap.diagLog.error("Error creating event tap \"\(label)\"")
        }
    }

    /// Splices a tap into the event stream for a single event type.
    ///
    /// An active filter decides what the rest of the system sees: return the
    /// received event to let it continue, return a different event to swap it
    /// out, or return nil to drop it. A passive listener only observes,
    /// whatever its callback returns is ignored.
    ///
    /// The tap starts out inert; call enable() to begin receiving events.
    ///
    /// - Parameters:
    ///   - label: A name for the tap, used in logs and while debugging.
    ///   - type: The kind of event the tap wants to see.
    ///   - location: The stage of the event stream to splice into.
    ///   - placement: Where the tap sits among the taps already installed
    ///     at location.
    ///   - option: Whether the tap may alter the stream or merely watch it.
    ///   - callback: The closure invoked for each event the tap receives.
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

    /// Handles one event delivered by Core Graphics.
    ///
    /// Returns the event to forward, possibly a replacement supplied by the
    /// callback, or nil to take the event out of the stream.
    private func process(_ event: CGEvent, of type: CGEventType) -> Unmanaged<CGEvent>? {
        if Self.disableNotices.contains(type) {
            // The window server switched us off. Turn the tap back on and
            // swallow the notification, which is not a real event.
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
            Self.diagLog.warning("Event tap \"\(label)\" was disabled by \(reason), re-enabling")
            enable()
            return nil
        }
        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }
        guard let forwarded = callback(self, event) else {
            return nil
        }
        return Unmanaged.passUnretained(forwarded)
    }

    /// Opens the Mach port and run loop source for the stored creation
    /// parameters and records them in state.
    ///
    /// On success the tap takes an extra retain on itself, which is what the
    /// opaque userInfo pointer stands for; teardownPort() gives it back.
    /// On failure nothing is registered and no retain is left outstanding.
    private func openPort() -> PortResult {
        guard Self.requestTapCreation() else {
            return .poolExhausted
        }

        let retained = Unmanaged.passRetained(self)
        guard
            let machPort = creationLocation.openMachPort(
                mask: creationMask,
                place: creationPlacement,
                options: creationOption,
                userInfo: retained.toOpaque()
            ),
            let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        else {
            retained.release()
            return .refused
        }

        // Core Graphics creates taps enabled, before they have a run-loop
        // source. Keep this one inert until enable() attaches its source;
        // otherwise conditional startup mistakes an unserviced tap for ready.
        CGEvent.tapEnable(tap: machPort, enable: false)
        Self.registerTap(self)

        // withLockUnchecked (not withLock) because machPort/source
        // are CFMachPort/CFRunLoopSource, non-Sendable types that
        // withLock's @Sendable closure can't capture. Safe here: this is
        // the only reference to these locals, handed off to state under
        // the lock and never touched outside it again.
        state.withLockUnchecked { state in
            state.machPort = machPort
            state.source = source
        }

        return .opened
    }

    /// Detaches the run loop source, invalidates the Mach port, and hands back
    /// the retain that openPort() took.
    ///
    /// Running this twice is harmless: the second pass finds state already
    /// emptied out and does nothing.
    private func teardownPort() {
        state.withLock { state in
            if let machPort = state.machPort {
                CGEvent.tapEnable(tap: machPort, enable: false)
            }
            if let source = state.source {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
                state.source = nil
            }
            if let machPort = state.machPort {
                CFMachPortInvalidate(machPort)
                state.machPort = nil
                Unmanaged.passUnretained(self).release()
            }
        }
    }

    /// Checks whether the tap is still valid and attempts to recreate
    /// it if the Mach port has been invalidated. Returns true if the
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
        if invalidated {
            Self.diagLog.warning("Event tap \"\(tapLabel)\" was invalidated, cannot recreate")
            return false
        }
        if hasMachPort {
            Self.diagLog.warning("Event tap \"\(tapLabel)\" Mach port is invalid, attempting recreation")
        } else {
            // Tap was never successfully created.
            Self.diagLog.warning("Event tap \"\(tapLabel)\" has no Mach port, attempting creation")
        }
        return recreate()
    }

    /// Tears down the current tap and creates a new one using the
    /// original parameters. Returns true on success.
    private func recreate() -> Bool {
        let tapLabel = self.label
        // Clean up the old tap without setting isInvalidated (we want to reuse this instance).
        Self.unregisterTap(self)
        teardownPort()

        switch openPort() {
        case .opened:
            Self.diagLog.info("Successfully recreated event tap \"\(tapLabel)\"")
            return true
        case .poolExhausted:
            Self.diagLog.warning("Too many active EventTaps, cannot recreate \"\(tapLabel)\"")
            return false
        case .refused:
            Self.diagLog.error("Failed to recreate event tap \"\(tapLabel)\"")
            return false
        }
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
        teardownPort()
    }

    /// Switches the tap on and attaches it to the run loop.
    func enable() {
        state.withLock { state in
            guard let machPort = state.machPort, let source = state.source else {
                return
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: machPort, enable: true)
        }
    }

    /// Detaches the tap from the run loop and switches it off.
    func disable() {
        state.withLock { state in
            guard let machPort = state.machPort, let source = state.source else {
                return
            }
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
    }
}
