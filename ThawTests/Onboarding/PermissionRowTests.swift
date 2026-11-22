//
//  PermissionRowTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// What the permissions window's rows offer as a request is answered, on the preview's stubs.
@MainActor
@Suite("Permission rows")
struct PermissionRowTests {
    private final class PreviewToggle {
        var isOn = false
    }

    @Test("A request waits for its answer until the next check declines it")
    func waitsUntilDeclined() {
        let permissions = OnboardingPreview.permissions(answer: .declines)
        defer { permissions.stopAllChecks() }
        let accessibility = permissions.accessibility
        #expect(!accessibility.awaitingPromptAnswer)
        accessibility.performRequest()
        #expect(accessibility.awaitingPromptAnswer)
        accessibility.handlePollTick()
        #expect(!accessibility.awaitingPromptAnswer)
        #expect(accessibility.wasDeclined)
    }

    @Test("After a declined prompt the row keeps waiting until the grant lands")
    func waitsAfterDecline() {
        let grant = PreviewToggle()
        let accessibility = AccessibilityPermission(stub: PermissionStub(
            check: { grant.isOn },
            request: { completion in completion(false, true) }
        ))
        defer { accessibility.stopCheck() }
        #expect(!accessibility.waitsAfterDecline)
        accessibility.performRequest()
        #expect(!accessibility.waitsAfterDecline, "the prompt is still up")
        accessibility.handlePollTick()
        #expect(accessibility.wasDeclined)
        #expect(accessibility.waitsAfterDecline)
        grant.isOn = true
        accessibility.handlePollTick()
        #expect(accessibility.hasPermission)
        #expect(!accessibility.isWaitingForGrant)
        #expect(!accessibility.waitsAfterDecline)
    }

    @Test("A dismissed file panel offers the file again instead of waiting")
    func filePanelDoesNotWait() {
        let permissions = OnboardingPreview.permissions(answer: .declines)
        defer { permissions.stopAllChecks() }
        let layout = permissions.fullDiskAccess
        layout.performRequest()
        layout.handlePollTick()
        #expect(layout.offersChoosingFileAgain)
        #expect(!layout.waitsAfterDecline)
    }

    @Test("A granted request does not wait")
    func grantDoesNotWait() {
        let permissions = OnboardingPreview.permissions()
        defer { permissions.stopAllChecks() }
        permissions.fullDiskAccess.performRequest()
        #expect(permissions.fullDiskAccess.hasPermission)
        #expect(!permissions.fullDiskAccess.awaitingPromptAnswer)
    }

    @Test("Only a declined Menu Bar Layout Access offers the file again")
    func choosingFileAgain() {
        let permissions = OnboardingPreview.permissions(answer: .declines)
        defer { permissions.stopAllChecks() }
        for permission in permissions.allPermissions {
            #expect(!permission.offersChoosingFileAgain, "nothing was declined yet")
            permission.performRequest()
            permission.handlePollTick()
            #expect(permission.wasDeclined)
        }
        #expect(permissions.fullDiskAccess.offersChoosingFileAgain)
        #expect(!permissions.accessibility.offersChoosingFileAgain, "no file panel")
        #expect(!permissions.screenRecording.offersChoosingFileAgain, "no file panel")
        #expect(
            !permissions.controlCenterAppList.offersChoosingFileAgain,
            "without a settings pane its own button opens the panel again"
        )
        #expect(
            permissions.fullDiskAccess.rowSubtitle(grantedWhileShown: false)
                == String(localized: "Choose the file again, or turn on Full Disk Access for \(Constants.displayName) instead.")
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
