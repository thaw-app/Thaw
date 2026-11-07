//
//  SwapBarTurnOffTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The Swap Bar's ✕ was labelled Close but turned the feature off, with no way back shown.
@MainActor
@Suite("Swap Bar turn off", .serialized, .scratchDefaults)
struct SwapBarTurnOffTests {
    @Test("Turning it off clears the setting and says where to turn it back on")
    func turnOffSaysWhereToComeBack() {
        let settings = AppState().settings.advanced
        settings.enableSwapBar = true
        var shown: (symbol: String, text: String)?
        SwapBarTurnOff.turnOff(settings) { shown = ($0, String(localized: $1)) }
        #expect(!settings.enableSwapBar)
        #expect(shown?.text.contains("Visibility") == true)
        #expect(String(localized: SwapBarTurnOff.title) == "Turn Off Swap Bar")
    }
}
