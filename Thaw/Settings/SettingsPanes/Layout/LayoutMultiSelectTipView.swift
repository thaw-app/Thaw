//
//  LayoutMultiSelectTipView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI
import TipKit

/// The multi-select tip as a hint card above the layout bars. Draws nothing once TipKit retires the tip.
struct LayoutMultiSelectTipView: View {
    /// Whether the pane's first-visit limitations card is up, which holds the tip back until it is dismissed.
    let isLimitationsCardShowing: Bool

    private let tip = LayoutMultiSelectTip()

    var body: some View {
        TipView(tip)
            .tipViewStyle(ThawHintTipViewStyle())
            .onChange(of: isLimitationsCardShowing, initial: true) { _, isShowing in
                LayoutMultiSelectTip.isLimitationsCardShowing = isShowing
            }
    }
}
