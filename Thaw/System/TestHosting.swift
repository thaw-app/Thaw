//
//  TestHosting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Unit tests run inside Thaw itself, so code that would act on the live system checks this first.
nonisolated enum TestHosting {
    static func isActive(environment: [String: String]) -> Bool {
        TestHostEnvironment.isActive(environment)
    }

    static var isActiveInProcess: Bool {
        isActive(environment: ProcessInfo.processInfo.environment)
    }

    static let preferencesSuiteName = "com.stonerl.Thaw.testhost"

    /// Under tests, swaps in an empty private preferences suite so a run never touches the person's own. Returns whether it did.
    @discardableResult
    static func isolatePreferencesWhenHosted() -> Bool {
        guard isActiveInProcess else { return false }
        isolatePreferences()
        return true
    }

    static func isolatePreferences() {
        UserDefaults().removePersistentDomain(forName: preferencesSuiteName)
        guard let suite = UserDefaults(suiteName: preferencesSuiteName) else { return }
        Defaults.store = suite
    }
}
