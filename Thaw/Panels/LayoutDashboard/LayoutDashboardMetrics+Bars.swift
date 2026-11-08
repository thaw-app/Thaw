//
//  LayoutDashboardMetrics+Bars.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics

extension LayoutDashboardMetrics {
    /// Around the bars: the hint under them, the form's insets and the toolbar the content runs under.
    static let barsChrome: CGFloat = 90
    /// The share of the window the bars may take, so the list and the editor keep the rest.
    static let barsMaxShare: CGFloat = 0.55

    /// The bars' pane, fitted to the bars once they are measured and capped by the window.
    /// Past the cap the pane scrolls.
    ///
    /// - Parameters:
    ///   - contentHeight: The bars' measured height, or nil before they first lay out.
    ///   - sections: The sections shown, for the estimate before the bars are measured.
    ///   - available: The window's content height, or nil before it is measured.
    static func barsHeight(fitting contentHeight: CGFloat?, sections: Int, available: CGFloat?) -> CGFloat {
        let fitted = contentHeight.map { $0 + barsChrome } ?? barsHeight(sections: sections)
        guard let available else { return fitted }
        return min(fitted, max(available * barsMaxShare, barsHeight(sections: 1)))
    }
}
