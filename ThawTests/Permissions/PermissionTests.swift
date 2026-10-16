//
//  PermissionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// Covers ``Permission``'s request/poll cycle through its injected closures,
/// so nothing here touches the real TCC database.
@MainActor
@Suite("Permission request polling")
struct PermissionTests {
    @Test("A request restarts polling after checks have been stopped", .timeLimit(.minutes(1)))
    func performRequestRestartsPollingAfterChecksStop() async throws {
        var isGranted = false
        var requestCount = 0
        var openedSettingsURLs = [URL]()
        let settingsURL = try #require(
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

        // `onChange` fires on every poll tick, and `resume` traps on a second
        // call, so latch the first grant and ignore later ticks.
        await confirmation("Permission grant is observed after polling restarts") { granted in
            await withCheckedContinuation { continuation in
                var hasResumed = false
                permission.onChange = {
                    guard permission.hasPermission, !hasResumed else {
                        return
                    }
                    hasResumed = true
                    granted()
                    continuation.resume()
                }
            }
        }

        #expect(requestCount == 2)
        #expect(openedSettingsURLs == [settingsURL, settingsURL])
        #expect(permission.hasPermission)
    }

    /// Built without `openSettings`, so the default `NSWorkspace` closure is stored.
    /// `settingsURL` is `nil`, so nothing is ever opened.
    @Test("A permission built without an opener still requests and polls")
    func defaultOpenSettingsIsInstalled() {
        var isGranted = false
        var requestCount = 0
        let permission = Permission(
            title: "Test Permission",
            iconName: "checkmark",
            iconColor: .blue,
            details: ["only used by the test suite"],
            isRequired: false,
            settingsURL: nil,
            check: { isGranted },
            request: { requestCount += 1 }
        )
        defer { permission.stopCheck() }

        #expect(!permission.hasPermission)

        isGranted = true
        permission.performRequest()

        #expect(requestCount == 1)
        // `performRequest` restarts polling, and the restart's first tick
        // is delivered synchronously, so the grant is already visible.
        #expect(permission.hasPermission)
    }

    @Test("A permission records the details it was built with")
    func permissionKeepsItsDescriptiveFields() {
        let permission = Permission(
            title: "Test Permission",
            iconName: "record.circle",
            iconColor: .red,
            details: ["first", "second"],
            isRequired: true,
            settingsURL: nil,
            check: { true },
            request: {}
        )
        defer { permission.stopCheck() }

        #expect(permission.title == "Test Permission")
        #expect(permission.iconName == "record.circle")
        #expect(permission.iconColor == Color.red)
        #expect(permission.details == ["first", "second"])
        #expect(permission.isRequired)
        #expect(permission.hasPermission)
    }
}
