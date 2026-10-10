//
//  EnergyModePicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - EnergyModePicker

/// The Energy Mode picker, shared by the trigger row and the compound
/// condition editor.
struct EnergyModePicker: View {
    @Binding var match: EnergyModeMatch

    var body: some View {
        IcePicker("Mode", selection: $match) {
            ForEach(options) { option in
                Text(option.displayString).tag(option)
            }
        }
    }

    /// High Power is offered only on Macs that have it. A trigger already
    /// set to High Power keeps showing it either way, so moving settings
    /// between Macs never silently rewrites the selection.
    private var options: [EnergyModeMatch] {
        let selectable = EnergyModeMatch.selectableCases(
            highPowerModeSupported: EnergyModeMonitor.isHighPowerModeSupported
        )
        return selectable.contains(match) ? selectable : selectable + [match]
    }
}
