//
//  PermissionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI
@testable import Thaw
import XCTest

// MARK: - Permission Tests

@MainActor
final class PermissionTests: XCTestCase {
    func testPerformRequestRestartsPollingAfterChecksStop() {
        var isGranted = false
        var requestCount = 0
        let permission = Permission(
            title: "Test Permission",
            iconName: "checkmark",
            iconColor: .blue,
            details: [],
            isRequired: false,
            settingsURL: nil,
            check: { isGranted },
            request: { requestCount += 1 }
        )

        permission.stopCheck()
        permission.performRequest()
        isGranted = true

        let granted = expectation(description: "Permission grant is observed after polling restarts")
        let cancellable = permission.$hasPermission
            .filter(\.self)
            .sink { _ in granted.fulfill() }

        wait(for: [granted], timeout: 5)

        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(permission.hasPermission)
        withExtendedLifetime(cancellable) {}
    }
}
