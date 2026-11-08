//
//  LogRotationInterval.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI

/// How often a new log file starts regardless of size. The raw values are Thaw 2's stored ones.
nonisolated enum LogRotationInterval: String, CaseIterable, Identifiable, Sendable {
    case off
    case hourly
    case daily

    var id: String {
        rawValue
    }

    var seconds: TimeInterval {
        switch self {
        case .off: 0
        case .hourly: 3600
        case .daily: 86400
        }
    }

    var localized: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .hourly: "Hourly"
        case .daily: "Daily"
        }
    }
}
