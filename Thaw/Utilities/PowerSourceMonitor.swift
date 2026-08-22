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

// MARK: - PowerState

/// A snapshot of the system's power source at a single point in time.
///
/// Used by the menu bar item triggers system to decide whether a
/// battery- or power-based condition is currently satisfied.
struct PowerState: Equatable {
    /// The current battery charge as a percentage in the range `0...100`,
    /// or `nil` when the machine has no battery (e.g. a desktop Mac).
    var batteryPercentage: Double?

    /// A Boolean value that indicates whether the machine is currently
    /// drawing from an AC power source.
    var isOnACPower: Bool

    /// A Boolean value that indicates whether the battery is currently
    /// charging.
    var isCharging: Bool

    /// A Boolean value that indicates whether the machine has a battery.
    var hasBattery: Bool {
        batteryPercentage != nil
    }
}

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
        guard runLoopSource == nil else { return }

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
        return state(from: descriptions)
    }

    /// Reduces an IOPS source list without mixing fields from different
    /// devices. Prefer the Mac's internal battery; fall back to a UPS-like
    /// capacity source only when no internal battery exists. An empty list is
    /// the normal desktop-Mac case and therefore means AC, not battery.
    static func state(from descriptions: [[String: Any]]) -> PowerState {
        let preferred = descriptions.first {
            ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        } ?? descriptions.first { description in
            guard
                let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            else { return false }
            return maximum > 0
        }

        let batteryPercentage: Double? = preferred.flatMap { description in
            guard
                let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
                let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
                maximum > 0
            else { return nil }
            return min(100, max(0, (current / maximum) * 100))
        }

        let sourceState = preferred?[kIOPSPowerSourceStateKey] as? String
        let anySourceReportsAC = descriptions.contains {
            ($0[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }
        let isOnACPower = sourceState.map { $0 == kIOPSACPowerValue }
            ?? (descriptions.isEmpty || anySourceReportsAC)
        let isCharging = (preferred?[kIOPSIsChargingKey] as? Bool) ?? false

        return PowerState(
            batteryPercentage: batteryPercentage,
            isOnACPower: isOnACPower,
            isCharging: isCharging
        )
    }
}
