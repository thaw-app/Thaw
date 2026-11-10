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
    @State private var tip: LayoutMultiSelectTip?

    var body: some View {
        Group {
            if let tip, FeatureTips.shared.isConfigured {
                // The style draws its own glass card, so neither TipView nor the form row draws one behind it.
                TipView(tip)
                    .tipViewStyle(ThawHintTipViewStyle())
                    .tipBackground(Color.clear)
                    .listRowBackground(Color.clear)
            }
        }
        .onAppear {
            FeatureTips.configureIfNeededForLayout()
            if FeatureTips.shared.isConfigured, tip == nil {
                tip = LayoutMultiSelectTip()
            }
        }
    }
}
