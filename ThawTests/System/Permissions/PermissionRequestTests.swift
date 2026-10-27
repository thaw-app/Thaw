//
//  PermissionRequestTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

/// How a permission handles a request, a refresh and its copy, with the system checks replaced by stubs.
@MainActor
@Suite("Permission requests")
struct PermissionRequestTests {
    private final class Stub {
        var granted = false
        var asyncGranted = false
        var requests = 0
        var changes = 0
    }

    private func makePermission(
        stub: Stub,
        shortDetails: [String]? = nil,
        isRequired: Bool = true,
        asyncCheck: Bool = false,
        reply: (granted: Bool, prompted: Bool) = (false, true)
    ) -> Permission {
        let permission = Permission(
            title: "Stub",
            iconName: "star",
            iconColor: .orange,
            details: ["Long detail"],
            shortDetails: shortDetails,
            isRequired: isRequired,
            // Nil, so a request that falls back to System Settings opens nothing.
            settingsURL: nil,
            check: { stub.granted },
            asyncCheck: asyncCheck ? { stub.asyncGranted } : nil,
            request: { completion in
                stub.requests += 1
                completion(reply.granted, reply.prompted)
            },
            pollInterval: 3600,
            ungrantedPollBudget: 10
        )
        permission.onChange = { stub.changes += 1 }
        return permission
    }

    @Test("A granted request publishes the grant and stops polling")
    func grantedRequest() {
        let stub = Stub()
        let permission = makePermission(stub: stub, reply: (true, false))
        permission.performRequest()
        #expect(stub.requests == 1)
        #expect(permission.hasPermission)
        #expect(!permission.isPolling)
        #expect(stub.changes == 1)
    }

    @Test("A request that showed no prompt falls back to the settings pane and is not a decline")
    func unpromptedRequest() {
        let stub = Stub()
        let permission = makePermission(stub: stub, reply: (false, false))
        permission.performRequest()
        permission.handlePollTick()
        #expect(!permission.hasPermission)
        #expect(!permission.wasDeclined)
        #expect(!permission.hasSettingsPane)
    }

    @Test("A grant after a decline clears the decline")
    func grantClearsDecline() {
        let stub = Stub()
        let permission = makePermission(stub: stub)
        permission.performRequest()
        permission.handlePollTick()
        #expect(permission.wasDeclined)
        stub.granted = true
        permission.refreshStatus()
        #expect(permission.hasPermission)
        #expect(!permission.wasDeclined)
    }

    @Test("A synchronous refresh only notifies on a real change")
    func refreshNotifiesOnChange() {
        let stub = Stub()
        let permission = makePermission(stub: stub)
        permission.refreshStatus()
        #expect(stub.changes == 0)
        stub.granted = true
        permission.refreshStatus()
        permission.refreshStatus()
        #expect(stub.changes == 1)
        stub.granted = false
        permission.refreshStatus()
        #expect(!permission.hasPermission)
        #expect(stub.changes == 2)
    }

    @Test("The asynchronous refresh asks the slower probe only when the quick check says no")
    func asyncRefresh() async {
        let stub = Stub()
        let permission = makePermission(stub: stub, asyncCheck: true)
        stub.asyncGranted = true
        await permission.refreshStatus()
        #expect(permission.hasPermission)

        let quick = Stub()
        quick.granted = true
        let other = makePermission(stub: quick, asyncCheck: true)
        await other.refreshStatus()
        #expect(other.hasPermission)
    }

    @Test("Without a slower probe the asynchronous refresh uses the quick check")
    func asyncRefreshWithoutProbe() async {
        let stub = Stub()
        let permission = makePermission(stub: stub)
        await permission.refreshStatus()
        #expect(!permission.hasPermission)
        stub.granted = true
        await permission.refreshStatus()
        #expect(permission.hasPermission)
    }

    @Test("Onboarding uses the short copy when there is one")
    func onboardingCopy() {
        let stub = Stub()
        #expect(makePermission(stub: stub).onboardingDetails == ["Long detail"])
        #expect(makePermission(stub: stub, shortDetails: ["Short"]).onboardingDetails == ["Short"])
    }

    @Test("Stopping the check disarms the poll and opening a missing pane does nothing")
    func stopCheck() {
        let stub = Stub()
        let permission = makePermission(stub: stub)
        #expect(permission.isPolling)
        permission.stopCheck()
        #expect(!permission.isPolling)
        permission.openSettingsPane()
        #expect(!permission.hasPermission)
    }

    @Test("The label and status control draw for each state", arguments: [false, true])
    func viewsRender(granted: Bool) throws {
        let stub = Stub()
        stub.granted = granted
        let required = makePermission(stub: stub)
        let optional = makePermission(stub: stub, isRequired: false)
        defer {
            required.stopCheck()
            optional.stopCheck()
        }
        let view = VStack {
            PermissionLabel(permission: required, titleFont: .headline, badgePlacement: .adjacent)
            PermissionLabel(permission: optional, badgePlacement: .trailing)
            PermissionLabel(permission: optional, badgePlacement: .below)
            PermissionStatusControl(permission: required, layout: .inline)
            PermissionStatusControl(permission: optional, layout: .filled)
        }
        let render = OffscreenRender(view.frame(width: 320, height: 240), size: CGSize(width: 320, height: 240))
        #expect(try render.pixels().contains { $0 != 0 })
    }

    @Test("The optional badge makes the label taller only when it sits below")
    func badgeBelowIsTaller() {
        let stub = Stub()
        let optional = makePermission(stub: stub, isRequired: false)
        defer { optional.stopCheck() }
        let adjacent = OffscreenRender(PermissionLabel(permission: optional, badgePlacement: .adjacent), size: CGSize(width: 300, height: 80))
        let below = OffscreenRender(PermissionLabel(permission: optional, badgePlacement: .below), size: CGSize(width: 300, height: 80))
        #expect(below.host.fittingSize.height > adjacent.host.fittingSize.height)
    }
}

/// The app's own permission set, read from the live system without asking for anything.
@MainActor
@Suite("App permissions")
struct AppPermissionsTests {
    @Test("Required permissions come first and the state matches the grants")
    func stateMatchesGrants() {
        let permissions = AppPermissions()
        defer { permissions.stopAllChecks() }
        #expect(permissions.allPermissions.count == 4)
        #expect(!permissions.requiredPermissions.contains { !$0.isRequired })
        #expect(!permissions.allPermissions.prefix(2).contains { !$0.isRequired })
        permissions.refreshPermissionsState()
        let expected: AppPermissions.PermissionsState = if permissions.allPermissions.allSatisfy(\.hasPermission) {
            .hasAll
        } else if permissions.requiredPermissions.allSatisfy(\.hasPermission) {
            .hasRequired
        } else {
            .missing
        }
        // Only the synchronous refresh: the asynchronous one may probe Screen Recording.
        #expect(permissions.permissionsState == expected)
    }

    @Test("Stopping every check leaves no poll armed")
    func stopAll() {
        let permissions = AppPermissions()
        permissions.stopAllChecks()
        #expect(permissions.allPermissions.allSatisfy { !$0.isPolling })
    }

    @Test("Each permission names itself and its settings route")
    func permissionCopy() {
        let permissions = AppPermissions()
        defer { permissions.stopAllChecks() }
        #expect(permissions.accessibility.hasSettingsPane)
        #expect(permissions.screenRecording.hasSettingsPane)
        #expect(permissions.fullDiskAccess.hasSettingsPane)
        #expect(!permissions.controlCenterAppList.hasSettingsPane)
        #expect(!permissions.screenRecording.isRequired)
        #expect(!permissions.controlCenterAppList.isRequired)
        for permission in permissions.allPermissions {
            #expect(!permission.title.isEmpty)
            #expect(!permission.details.isEmpty)
            #expect(!permission.onboardingDetails.isEmpty)
        }
    }
}
