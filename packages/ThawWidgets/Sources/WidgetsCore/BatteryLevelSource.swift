//  Adapted from Barometer (https://github.com/mackid1993/Barometer)
//  Copyright (Barometer) © 2026 mackid1993. Used with permission.
//  Licensed under the GNU GPLv3
//
//  BatteryLevelSource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import IOKit.ps
import MenuBarModel

/// Reads the current battery charge level from IOKit.
enum BatteryLevelSource {
    /// Current battery charge as a fraction of maximum (0–1).
    static func level() -> Double {
        reading().level
    }

    /// The charge and whether it's charging, from one read of the power source.
    static func reading() -> (level: Double, isCharging: Bool) {
        guard let description = description() else { return (0, false) }
        return (level(from: description), isCharging(from: description))
    }

    /// The first power source's description, or nil on a Mac without one.
    private static func description() -> [String: Any]? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let handles = Bridging.arrayValue(of: IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()), let handle = handles.first
        else { return nil }
        // The list vends opaque handles, not dictionaries; casting them directly fails the bridge.
        return Bridging.dictionaryValue(of: IOPSGetPowerSourceDescription(snapshot, handle as CFTypeRef)?.takeUnretainedValue())
    }

    /// Plugged in but held at a charge limit isn't charging.
    static func isCharging(from description: [String: Any]) -> Bool {
        description[kIOPSIsChargingKey] as? Bool ?? false
    }

    /// The charge fraction a power source description reports.
    static func level(from description: [String: Any]) -> Double {
        let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 1
        guard max > 0 else { return 0 }
        return Double(capacity) / Double(max)
    }
}
