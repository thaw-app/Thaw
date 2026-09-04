//
//  EnergyMode.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// MARK: - EnergyMode

/// The macOS Energy Mode in effect for the active power source.
///
/// System Settings > Battery offers up to three modes. Only Low Power Mode
/// has a public API (`ProcessInfo.isLowPowerModeEnabled`); High Power Mode
/// is offered on a subset of Macs and is published only through power
/// management's dynamic store entry. ``EnergyModeMonitor`` reads both.
enum EnergyMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case low
    case automatic
    case high

    var id: String {
        rawValue
    }

    var displayString: String {
        switch self {
        case .low: "Low Power"
        case .automatic: "Automatic"
        case .high: "High Power"
        }
    }
}
