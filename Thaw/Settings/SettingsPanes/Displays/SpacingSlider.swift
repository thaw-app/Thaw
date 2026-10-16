//
//  SpacingSlider.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The menu bar item spacing slider: two points a step, filling from the default either way.
struct SpacingSlider<Label: View>: View {
    @Binding var value: CGFloat
    @ViewBuilder let label: () -> Label

    var body: some View {
        ThawSlider(
            value: $value,
            in: -16 ... 16,
            step: 2,
            fillsFromCenter: true,
            valueLabel: label
        )
    }
}
