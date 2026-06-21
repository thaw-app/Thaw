//
//  PermissionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

@MainActor
final class PermissionTests: XCTestCase {
    func testScreenCapturePermissionChecksAllEligibleWindows() {
        XCTAssertTrue(
            ScreenCapture.permissionGranted(
                windowTitles: [nil, "Clock"],
                preflightResult: false
            )
        )
    }

    func testScreenCapturePermissionUsesPreflightFallback() {
        XCTAssertTrue(
            ScreenCapture.permissionGranted(
                windowTitles: [nil],
                preflightResult: true
            )
        )
    }

    func testScreenCapturePermissionRejectsUntitledWindowsWithoutPreflight() {
        XCTAssertFalse(
            ScreenCapture.permissionGranted(
                windowTitles: [nil, nil],
                preflightResult: false
            )
        )
    }

    func testPerformRequestRefreshesPermissionState() {
        var isGranted = false
        let permission = Permission(
            title: "Test Permission",
            iconName: "checkmark",
            iconColor: .green,
            details: [],
            isRequired: true,
            settingsURL: nil,
            check: { isGranted },
            request: { isGranted = true }
        )

        XCTAssertFalse(permission.hasPermission)

        permission.performRequest()

        XCTAssertTrue(permission.hasPermission)
    }
}
