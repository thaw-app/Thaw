//
//  SecondsLabel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

public struct SecondsLabel: View {
    let value: Double

    public init(value: Double) {
        self.value = value
    }

    /// Formatted as a duration measurement, so each language gets its own
    /// unit word and plural ("1 second", "2.5 seconds"), not English only.
    public var body: Text {
        Text(
            Measurement(value: value, unit: UnitDuration.seconds)
                .formatted(.measurement(width: .wide, numberFormatStyle: .number.precision(.fractionLength(0 ... 1))))
        )
        .font(ThawType.metric)
    }
}
