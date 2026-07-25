//
//  PermissionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
@testable import Thaw
import XCTest

// MARK: - Permission Tests

@MainActor
final class PermissionTests: XCTestCase {
    func testPerformRequestRestartsPollingAfterChecksStop() throws {
        var isGranted = false
        var requestCount = 0
        var openedSettingsURLs = [URL]()
        let settingsURL = try XCTUnwrap(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
        let permission = Permission(
            title: "Test Permission",
            iconName: "checkmark",
            iconColor: .blue,
            details: [],
            isRequired: false,
            settingsURL: settingsURL,
            check: { isGranted },
            request: { requestCount += 1 },
            openSettings: { url in
                openedSettingsURLs.append(url)
                return true
            }
        )

        permission.stopCheck()
        permission.performRequest()
        permission.stopCheck()
        permission.performRequest()
        isGranted = true

        let granted = expectation(description: "Permission grant is observed after polling restarts")
        permission.onChange = {
            if permission.hasPermission {
                granted.fulfill()
            }
        }

        wait(for: [granted], timeout: 5)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(openedSettingsURLs, [settingsURL, settingsURL])
        XCTAssertTrue(permission.hasPermission)
    }
}
