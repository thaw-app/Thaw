//
//  MacOSCompatibilityWarningTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("macOS compatibility warning")
struct MacOSCompatibilityWarningTests {
    @Test("macOS 27 and later show the warning", arguments: [27, 28])
    func unsupportedVersionsShowWarning(majorVersion: Int) {
        #expect(MacOSCompatibilityWarning.shouldShow(for: version(majorVersion)))
    }

    @Test("macOS 26 and earlier do not show the warning", arguments: [25, 26])
    func supportedVersionsDoNotShowWarning(majorVersion: Int) {
        #expect(!MacOSCompatibilityWarning.shouldShow(for: version(majorVersion)))
    }

    private func version(_ majorVersion: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0)
    }
}
