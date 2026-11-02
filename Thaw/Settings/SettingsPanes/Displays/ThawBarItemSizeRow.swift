//
//  ThawBarItemSizeRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The Thaw Bar's item size slider. Alpha until scaled captures are checked on
/// more displays.
struct ThawBarItemSizeRow: View {
    @Binding var scale: Double

    var body: some View {
        LabeledContent {
            ThawSlider(value: $scale, in: ThawBarItemSize.scaleRange, step: ThawBarItemSize.scaleStep) {
                Text(scale, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
        } label: {
            HStack(spacing: ThawSpacing.compact) {
                Text("Item size")
                ThawBadge.alpha
            }
        }
        .annotation("How large items are in the \(Constants.displayName) Bar. At 100% they match the menu bar; smaller sizes fit more items in a row.")
    }
}
