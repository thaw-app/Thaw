//
//  SwapBarTurnOff.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawUI

/// The Swap Bar's ✕ turns the feature off, not just the bar, so it says where to turn it back on.
@MainActor
enum SwapBarTurnOff {
    static let title: LocalizedStringResource = "Turn Off Swap Bar"

    static var notice: LocalizedStringResource {
        "Swap Bar is off. Turn it back on in Settings \(Constants.menuArrow) Visibility."
    }

    static func turnOff(
        _ settings: AdvancedSettings,
        showHUD: (String, LocalizedStringResource) -> Void = { ThawHUD.show(symbol: $0, text: $1) }
    ) {
        settings.enableSwapBar = false
        showHUD("rectangle.on.rectangle.slash", notice)
    }
}
