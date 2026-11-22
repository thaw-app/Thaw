//
//  PermissionStubTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Permissions whose system calls are replaced, as the onboarding previews use them.
@MainActor
@Suite("Permission stubs")
struct PermissionStubTests {
    private final class Grant {
        var isGranted = false
        var requests = 0
    }

    private func stub(_ grant: Grant, grants: Bool) -> PermissionStub {
        PermissionStub(
            check: { grant.isGranted },
            request: { completion in
                grant.requests += 1
                if grants {
                    grant.isGranted = true
                }
                completion(grants, !grants)
            }
        )
    }

    @Test("A stubbed permission keeps its copy and answers only from the stub")
    func stubReplacesSystemCalls() async {
        let grant = Grant()
        let permission = ScreenRecordingPermission(stub: stub(grant, grants: true))
        defer { permission.stopCheck() }
        #expect(permission.title == String(localized: "Screen Recording"))
        #expect(!permission.isRequired)
        #expect(permission.hasSettingsPane, "the pane is kept, and opening it does nothing")
        await permission.refreshStatus()
        #expect(!permission.hasPermission, "the asynchronous system probe is not used")
        permission.performRequest()
        #expect(grant.requests == 1)
        #expect(permission.hasPermission)
    }

    @Test("App permissions built from stubs report the stubs' grants")
    func appPermissionsFromStubs() {
        let granted = Grant()
        granted.isGranted = true
        let missing = Grant()
        let permissions = AppPermissions(
            accessibility: AccessibilityPermission(stub: stub(granted, grants: false)),
            screenRecording: ScreenRecordingPermission(stub: stub(missing, grants: false)),
            fullDiskAccess: FullDiskAccessPermission(stub: stub(granted, grants: false)),
            controlCenterAppList: ControlCenterAppListPermission(stub: stub(missing, grants: false))
        )
        defer { permissions.stopAllChecks() }
        #expect(permissions.permissionsState == .hasRequired)
    }

    @Test("The preview's permissions grant on request, or are declined at the next check")
    func previewAnswers() {
        let granting = OnboardingPreview.permissions(granted: [.accessibility])
        defer { granting.stopAllChecks() }
        #expect(granting.accessibility.hasPermission)
        #expect(granting.permissionsState == .missing)
        granting.fullDiskAccess.performRequest()
        #expect(granting.permissionsState == .hasRequired)

        let declining = OnboardingPreview.permissions(answer: .declines)
        defer { declining.stopAllChecks() }
        declining.accessibility.performRequest()
        #expect(!declining.accessibility.wasDeclined)
        declining.accessibility.handlePollTick()
        #expect(declining.accessibility.wasDeclined)
        #expect(!declining.accessibility.hasPermission)
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
