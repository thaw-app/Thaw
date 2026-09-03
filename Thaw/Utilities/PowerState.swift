//
//  PowerState.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

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

extension PowerState {
    /// Reduces an IOPS source list without mixing fields from different
    /// devices. Prefer the Mac's internal battery; fall back to a UPS-like
    /// capacity source only when no internal battery exists. An empty list is
    /// the normal desktop-Mac case and therefore means AC, not battery.
    init(descriptions: [[String: Any]]) {
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

        self.init(
            batteryPercentage: batteryPercentage,
            isOnACPower: isOnACPower,
            isCharging: isCharging
        )
    }
}
