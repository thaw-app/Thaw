//
//  TestHostEnvironment.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// Whether the process is hosting unit tests, from the variables Xcode sets when it runs them.
public nonisolated enum TestHostEnvironment {
    private static let keys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]

    public static func isActive(_ environment: [String: String]) -> Bool {
        keys.contains { environment[$0] != nil }
    }
}
