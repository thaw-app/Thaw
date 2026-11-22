//
//  PermissionRequestTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw
import ThawUI

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
        summary: String? = nil,
        isRequired: Bool = true,
        asyncCheck: Bool = false,
        reply: (granted: Bool, prompted: Bool) = (false, true)
    ) -> Permission {
        let permission = Permission(
            title: "Stub",
            iconName: "star",
            iconColor: .orange,
            details: ["Long detail"],
            summary: summary,
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

    @Test("Waiting for a grant ends when the poll gives up")
    func waitingEndsWithBudget() {
        let stub = Stub()
        let permission = makePermission(stub: stub)
        defer { permission.stopCheck() }
        permission.performRequest()
        #expect(permission.isWaitingForGrant)
        for _ in 0 ..< 10 {
            permission.handlePollTick()
        }
        #expect(!permission.isPolling)
        #expect(!permission.isWaitingForGrant)
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

    @Test("The summary falls back to the first detail")
    func summaryCopy() {
        let stub = Stub()
        #expect(makePermission(stub: stub).summary == "Long detail")
        #expect(makePermission(stub: stub, summary: "Short").summary == "Short")
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
            #expect(!permission.summary.isEmpty)
        }
    }
}

/// Permissions whose system calls are replaced, as the onboarding previews use them.
@MainActor
@Suite("Permission stubs")
struct PermissionStubTests {
    @Test("A stubbed permission keeps its settings pane and answers only from the stub")
    func stubReplacesSystemCalls() async {
        let grant = PreviewGrant()
        let permission = ScreenRecordingPermission(stub: OnboardingPreview.stub(grant, .grants))
        defer { permission.stopCheck() }
        #expect(permission.hasSettingsPane)
        await permission.refreshStatus()
        #expect(!permission.hasPermission, "the asynchronous system probe is not used")
        permission.performRequest()
        #expect(grant.requests == 1)
        #expect(permission.hasPermission)
    }

    @Test("The preview's permissions start with the given grants and grant on request")
    func previewGrants() {
        let permissions = OnboardingPreview.permissions(granted: [.accessibility])
        defer { permissions.stopAllChecks() }
        #expect(permissions.accessibility.hasPermission)
        #expect(permissions.permissionsState == .missing)
        permissions.fullDiskAccess.performRequest()
        #expect(permissions.permissionsState == .hasRequired)
    }

    @Test("The preview's Launch at Login stays on and writes nothing")
    func previewLaunchAtLogin() async {
        let setting = OnboardingPreview.launchAtLogin()
        await setting.refresh()
        #expect(setting.isEnabled)
        await setting.setEnabled(false)
        #expect(setting.isEnabled)
    }
}

/// What the permissions window's rows offer as a request is answered, on the preview's stubs.
@MainActor
@Suite("Permission rows")
struct PermissionRowTests {
    @Test("A prompt waits for its answer, and after a decline keeps waiting until the grant lands")
    func promptWaitsUntilGranted() {
        let grant = PreviewGrant()
        let accessibility = AccessibilityPermission(stub: OnboardingPreview.stub(grant, .declines))
        defer { accessibility.stopCheck() }
        #expect(!accessibility.awaitingPromptAnswer)
        accessibility.performRequest()
        #expect(accessibility.awaitingPromptAnswer)
        #expect(!accessibility.waitsAfterDecline, "the prompt is still up")
        accessibility.handlePollTick()
        #expect(!accessibility.awaitingPromptAnswer)
        #expect(accessibility.wasDeclined)
        #expect(accessibility.waitsAfterDecline)
        grant.isGranted = true
        accessibility.handlePollTick()
        #expect(accessibility.hasPermission)
        #expect(!accessibility.isWaitingForGrant)
        #expect(!accessibility.waitsAfterDecline)
    }

    @Test("A granted request does not wait")
    func grantDoesNotWait() {
        let permissions = OnboardingPreview.permissions()
        defer { permissions.stopAllChecks() }
        permissions.fullDiskAccess.performRequest()
        #expect(permissions.fullDiskAccess.hasPermission)
        #expect(!permissions.fullDiskAccess.isWaitingForGrant)
    }

    @Test("Only a dismissed Menu Bar Layout Access file panel offers the file again, instead of waiting")
    func choosingFileAgain() {
        let permissions = OnboardingPreview.permissions(answer: .declines)
        defer { permissions.stopAllChecks() }
        for permission in permissions.allPermissions {
            #expect(!permission.offersChoosingFileAgain, "nothing was declined yet")
            permission.performRequest()
            permission.handlePollTick()
            #expect(permission.wasDeclined)
        }
        let layout = permissions.fullDiskAccess
        #expect(layout.offersChoosingFileAgain)
        #expect(!layout.waitsAfterDecline)
        #expect(layout.rowSubtitle(grantedWhileShown: false) == layout.declinedHint)
        #expect(!permissions.accessibility.offersChoosingFileAgain, "no file panel")
        #expect(!permissions.screenRecording.offersChoosingFileAgain, "no file panel")
        #expect(
            !permissions.controlCenterAppList.offersChoosingFileAgain,
            "without a settings pane its own button opens the panel again"
        )
    }

    @Test("A file granted on the screen says a relaunch may be needed")
    func relaunchNote() {
        let note = String(localized: "You may need to quit and reopen \(Constants.displayName) before it takes effect.")
        let permissions = OnboardingPreview.permissions()
        defer { permissions.stopAllChecks() }
        for permission in permissions.allPermissions {
            #expect(permission.rowSubtitle(grantedWhileShown: false) == permission.summary)
            permission.performRequest()
            #expect(permission.hasPermission)
            #expect(permission.rowSubtitle(grantedWhileShown: false) == permission.summary, "granted before the screen opened")
        }
        #expect(permissions.fullDiskAccess.rowSubtitle(grantedWhileShown: true) == note)
        #expect(permissions.controlCenterAppList.rowSubtitle(grantedWhileShown: true) == note)
        #expect(permissions.accessibility.rowSubtitle(grantedWhileShown: true) == permissions.accessibility.summary)
        #expect(permissions.screenRecording.rowSubtitle(grantedWhileShown: true) == permissions.screenRecording.summary)
    }
}
