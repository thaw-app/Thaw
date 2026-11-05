//
//  TestHosting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Unit tests run inside Thaw itself, so code that would act on the live system checks this first.
nonisolated enum TestHosting {
    static func isActive(environment: [String: String]) -> Bool {
        TestHostEnvironment.isActive(environment)
    }
}
