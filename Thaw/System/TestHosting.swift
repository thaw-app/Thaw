//
//  TestHosting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Unit tests run inside Thaw itself, so code that would act on the live system checks this first.
nonisolated enum TestHosting {
    private static let environmentKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]

    static func isActive(environment: [String: String]) -> Bool {
        environmentKeys.contains { environment[$0] != nil }
    }
}
