//
//  PowerSourceMonitor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import IOKit.ps

// MARK: - PowerSourceMonitor

/// Observes the system's power source and publishes a ``PowerState``
/// whenever it changes.
///
/// Change notifications are delivered through an IOKit run-loop source on
/// the main run loop. A low-frequency safety timer republishes the current
/// state so a threshold crossing is never missed if a notification is
/// dropped.
@MainActor
final class PowerSourceMonitor: ObservableObject {
    /// The most recently observed power state.
    @Published private(set) var state: PowerState = PowerSourceMonitor.readCurrentState()

    /// The IOKit run-loop source delivering power source change callbacks.
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?

    /// A safety timer that refreshes the state in case a notification is
    /// dropped (battery percentage updates are otherwise infrequent).
    private nonisolated(unsafe) var safetyTimer: Timer?

    private let diagLog = DiagLog(category: "PowerSourceMonitor")

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        safetyTimer?.invalidate()
    }

    /// Begins observing power source changes. Safe to call more than once;
    /// subsequent calls are no-ops while already running.
    func start() {
        // Both handles are checked, not just the run loop source. When
        // `IOPSNotificationCreateRunLoopSource` fails, `runLoopSource` stays
        // nil while the safety timer is still scheduled, so guarding on the
        // source alone would let a second call schedule -- and leak -- another
        // timer, breaking the documented no-op contract.
        guard runLoopSource == nil, safetyTimer == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            // The callback is invoked on the run loop it was registered
            // on (the main run loop), but hop explicitly to keep the
            // @MainActor isolation contract clear.
            Task { @MainActor in
                monitor.refresh()
            }
        }

        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else {
            diagLog.warning("Failed to create power source notification run loop source")
        }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer

        refresh()
    }

    /// Stops observing power source changes.
    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        safetyTimer?.invalidate()
        safetyTimer = nil
    }

    /// Re-reads the current power state and publishes it when it differs
    /// from the last published value.
    func refresh() {
        let newState = Self.readCurrentState()
        if newState != state {
            state = newState
        }
    }

    /// Reads the current power state directly from IOKit.
    static func readCurrentState() -> PowerState {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            // No power source info available: treat as a desktop on AC.
            return PowerState(batteryPercentage: nil, isOnACPower: true, isCharging: false)
        }

        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return PowerState(descriptions: descriptions)
    }
}
