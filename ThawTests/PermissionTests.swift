//
//  PermissionTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
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

    func testScreenCapturePermissionPromptTemporarilyUsesRegularActivationPolicy() {
        var appliedPolicies = [NSApplication.ActivationPolicy]()
        var didActivate = false

        let restore = ScreenCapture.restoreActivationPolicyAfterScreenCapturePrompt(
            currentPolicy: .accessory,
            setActivationPolicy: { policy in
                appliedPolicies.append(policy)
                return true
            },
            activate: {
                didActivate = true
            }
        )

        XCTAssertEqual(appliedPolicies, [.regular])
        XCTAssertTrue(didActivate)

        restore?()

        XCTAssertEqual(appliedPolicies, [.regular, .accessory])
    }

    func testScreenCapturePermissionPromptDoesNotRestoreAlreadyRegularApp() {
        var appliedPolicies = [NSApplication.ActivationPolicy]()
        var didActivate = false

        let restore = ScreenCapture.restoreActivationPolicyAfterScreenCapturePrompt(
            currentPolicy: .regular,
            setActivationPolicy: { policy in
                appliedPolicies.append(policy)
                return true
            },
            activate: {
                didActivate = true
            }
        )

        XCTAssertTrue(appliedPolicies.isEmpty)
        XCTAssertTrue(didActivate)
        XCTAssertNil(restore)
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
