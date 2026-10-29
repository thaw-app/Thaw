//
//  MenuBarScanScope+WalkLabel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

extension MenuBarScanScope {
    /// The word the AX walk's summary log uses for this scope.
    nonisolated var walkLabel: String {
        switch self {
        case .discovery: "discovery"
        case .settledOwners: "settled"
        case .knownOwners, .requestedOwners, .itemOwners: "targeted"
        }
    }
}
