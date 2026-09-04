//
//  LogRotationInterval.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// How often diagnostic logs are rotated on a schedule, independently of the
/// size limit.
nonisolated enum LogRotationInterval: String, CaseIterable, Identifiable {
    case off
    case hourly
    case daily

    var id: String {
        rawValue
    }

    /// The interval in seconds, or `0` when scheduled rotation is off.
    var seconds: TimeInterval {
        switch self {
        case .off: 0
        case .hourly: 3600
        case .daily: 86400
        }
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .hourly: "Hourly"
        case .daily: "Daily"
        }
    }
}
