//
//  SpacingApplyModePersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers `DisplaySettingsManager.spacingApplyMode` persistence: the
/// `didSet` writes the raw value to `Defaults`, and a fresh manager reads
/// it back. The spacing manager sync is covered separately because it
/// needs an `AppState`. Added for the "disable the app restarts" request
/// on #1075.
@MainActor
@Suite("Spacing apply mode persistence", .serialized)
final class SpacingApplyModePersistenceTests {
    @Test("didSet persists the raw value, and a new manager reads it back")
    func didSetPersistsAndLoadReadsBack() throws {
        try withScratchDefaults { _ in
            let writer = DisplaySettingsManager()
            #expect(writer.spacingApplyMode == .relaunchApps)
            writer.spacingApplyMode = .writeOnly

            let reader = DisplaySettingsManager()
            #expect(reader.spacingApplyMode == .writeOnly)
        }
    }

    @Test("An unknown persisted value falls back to the default")
    func unknownRawValueFallsBack() throws {
        try withScratchDefaults { _ in
            Defaults.set("not-a-real-mode", forKey: .spacingApplyMode)
            let reader = DisplaySettingsManager()
            #expect(reader.spacingApplyMode == .relaunchApps)
        }
    }
}
