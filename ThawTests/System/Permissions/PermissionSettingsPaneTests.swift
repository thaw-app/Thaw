//
//  PermissionSettingsPaneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// How a permission with a settings pane sends the user there and hears the grant on return.
/// The pane is recorded, not opened, and activation is posted to a private center.
@MainActor
@Suite("Permission settings pane")
struct PermissionSettingsPaneTests {
    private final class Stub {
        var granted = false
        var opened: [URL] = []
    }

    private let pane = URL(fileURLWithPath: "/nonexistent/thaw-test-pane")

    private func makePermission(stub: Stub, center: NotificationCenter, prompted: Bool) -> Permission {
        Permission(
            title: "Stub",
            iconName: "star",
            iconColor: .orange,
            details: ["Detail"],
            isRequired: true,
            settingsURL: pane,
            check: { stub.granted },
            request: { completion in completion(false, prompted) },
            pollInterval: 3600,
            ungrantedPollBudget: 10,
            activationCenter: center,
            openURL: { stub.opened.append($0) }
        )
    }

    /// Activation is delivered on the main run loop, so the test waits for it rather than reading at once.
    private func waitForGrant(_ permission: Permission) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !permission.hasPermission, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A request that showed no prompt opens the settings pane")
    func unpromptedRequestOpensThePane() {
        let stub = Stub()
        let permission = makePermission(stub: stub, center: NotificationCenter(), prompted: false)
        defer { permission.stopCheck() }

        permission.performRequest()

        #expect(stub.opened == [pane])
    }

    @Test("A request that showed a prompt leaves the settings pane closed")
    func promptedRequestLeavesThePaneClosed() {
        let stub = Stub()
        let permission = makePermission(stub: stub, center: NotificationCenter(), prompted: true)
        defer { permission.stopCheck() }

        permission.performRequest()

        #expect(stub.opened.isEmpty)
    }

    @Test("A grant made in System Settings is recognized when the app becomes active again")
    func returnFromSettingsRefreshes() async {
        let stub = Stub()
        let center = NotificationCenter()
        let permission = makePermission(stub: stub, center: center, prompted: false)
        defer { permission.stopCheck() }
        permission.performRequest()

        stub.granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await waitForGrant(permission)

        #expect(permission.hasPermission)
    }

    @Test("Once checking stops, a return to the app no longer re-checks")
    func stoppedCheckIgnoresActivation() async throws {
        let stub = Stub()
        let center = NotificationCenter()
        let permission = makePermission(stub: stub, center: center, prompted: false)
        permission.performRequest()
        permission.stopCheck()

        stub.granted = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(200))

        #expect(!permission.hasPermission)
    }
}
