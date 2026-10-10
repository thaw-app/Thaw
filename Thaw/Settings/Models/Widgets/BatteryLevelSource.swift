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
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let handles = Bridging.arrayValue(of: IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()),
              let handle = handles.first,
              // The list vends opaque handles, not dictionaries; casting them
              // directly fails the bridge and reports 0%.
              let description: [String: Any] = Bridging.dictionaryValue(
                  of: IOPSGetPowerSourceDescription(snapshot, handle as CFTypeRef)?.takeUnretainedValue()
              )
        else { return 0 }
        let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 1
        guard max > 0 else { return 0 }
        return Double(capacity) / Double(max)
    }
}
