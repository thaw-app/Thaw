//
//  AppUIZoomModifierTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import Testing
import ThawUI

/// Imports ThawUI without @testable, so this stops compiling if the modifier's init stops being public.
@MainActor
@Suite("App UI zoom modifier")
struct AppUIZoomModifierTests {
    @Test("an app can construct the modifier")
    func constructsAcrossModules() {
        _ = AppUIZoomModifier()
    }
}
