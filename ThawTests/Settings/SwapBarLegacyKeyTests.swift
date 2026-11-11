//
//  SwapBarLegacyKeyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The Swap Bar was once the Transport Bar, saved under EnableTransportBar.
@MainActor
@Suite("Swap Bar's old key", .serialized, .scratchDefaults)
struct SwapBarLegacyKeyTests {
    @Test("Swap Bar turned off stays off when the old key says on, and the old key is removed")
    func currentKeyWins() {
        Defaults.set(true, forKey: .legacyEnableTransportBar)
        Defaults.set(false, forKey: .enableSwapBar)

        let settings = VisibilitySettings()
        settings.loadInitialState()

        #expect(!settings.enableSwapBar)
        #expect(Defaults.object(forKey: .enableSwapBar) as? Bool == false)
        #expect(Defaults.object(forKey: .legacyEnableTransportBar) == nil)
    }

    @Test("Without a Swap Bar setting of its own, the old key carries over once")
    func oldKeyCarriesOver() {
        Defaults.set(true, forKey: .legacyEnableTransportBar)

        let settings = VisibilitySettings()
        settings.loadInitialState()

        #expect(settings.enableSwapBar)
        #expect(Defaults.object(forKey: .enableSwapBar) as? Bool == true)
        #expect(Defaults.object(forKey: .legacyEnableTransportBar) == nil)
    }
}
