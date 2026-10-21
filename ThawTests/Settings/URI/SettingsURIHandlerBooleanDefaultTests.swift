//
//  SettingsURIHandlerBooleanDefaultTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``SettingsURIHandler/booleanValue(forKey:)`` for a key whose shipped
/// default is `true`.
///
/// `Defaults.bool` reads a key that was never written as `false`. For
/// `showDockIconWithSettings` that made `thaw://get` report `false` on a fresh
/// install and the first `thaw://toggle` write `true`, leaving the setting as
/// it was.
@MainActor
@Suite("Settings URI handler boolean defaults", .serialized)
struct SettingsURIHandlerBooleanDefaultTests {
    @Test("An unwritten key reports its shipped default through get")
    func absentKeyReportsShippedDefault() throws {
        try withScratchDefaults { _ in
            Defaults.removeObject(forKey: .showDockIconWithSettings)

            let value = try #require(
                SettingsURIHandler.getSettingValue(key: "showDockIconWithSettings", displayUUID: nil)
            )

            #expect(value["value"] as? Bool == Defaults.DefaultValue.showDockIconWithSettings)
        }
    }

    @Test("The first toggle of an unwritten key flips its shipped default")
    func firstToggleFlipsShippedDefault() throws {
        try withScratchDefaults { _ in
            Defaults.removeObject(forKey: .showDockIconWithSettings)

            #expect(SettingsURIHandler.handleToggle(key: "showDockIconWithSettings", sender: "test"))

            #expect(Defaults.object(forKey: .showDockIconWithSettings) as? Bool
                == !Defaults.DefaultValue.showDockIconWithSettings)
        }
    }

    @Test("A stored value wins over the shipped default")
    func storedValueWins() throws {
        try withScratchDefaults { _ in
            Defaults.set(false, forKey: .showDockIconWithSettings)

            #expect(!SettingsURIHandler.booleanValue(forKey: .showDockIconWithSettings))
        }
    }
}
