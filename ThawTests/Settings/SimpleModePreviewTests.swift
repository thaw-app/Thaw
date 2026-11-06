//
//  SimpleModePreviewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Simple Mode's sections preview")
struct SimpleModePreviewTests {
    @Test("The preview shows by default, and turning it off is saved")
    func previewSwitchIsSaved() throws {
        try ScratchDefaults.withStore(named: "SimpleModePreviewTests") { store in
            let settings = GeneralSettings()
            #expect(settings.simpleModeShowsPreview)
            settings.simpleModeShowsPreview = false
            #expect(store.object(forKey: "SimpleModeShowsPreview") as? Bool == false)
            let reloaded = GeneralSettings()
            reloaded.loadInitialState()
            #expect(!reloaded.simpleModeShowsPreview)
        }
    }
}
