//
//  LayoutMultiSelectTipView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI
import TipKit

/// The multi-select tip as a hint card above the layout bars. Draws nothing until TipKit shows the tip.
struct LayoutMultiSelectTipView: View {
    private let tip = LayoutMultiSelectTip()

    var body: some View {
        // The style draws its own glass card, so neither TipView nor the form row draws one behind it.
        TipView(tip)
            .tipViewStyle(ThawHintTipViewStyle())
            .tipBackground(Color.clear)
            .listRowBackground(Color.clear)
    }
}
