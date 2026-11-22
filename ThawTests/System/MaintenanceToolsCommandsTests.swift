//
//  MaintenanceToolsCommandsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// What the maintenance tools would run and report, checked without running anything.
@MainActor
@Suite("Maintenance tool commands")
struct MaintenanceToolsCommandsTests {
    private let suites = ScratchSuites(prefix: "MaintenanceToolsCommandsTests")

    @Test("Resetting permissions resets only Accessibility and Screen Recording, only for the given app")
    func permissionResetArguments() {
        #expect(MaintenanceTools.permissionResetArguments(bundleID: "com.example.app") == [
            ["reset", "Accessibility", "com.example.app"],
            ["reset", "ScreenCapture", "com.example.app"],
        ])
    }

    @Test("Resetting permissions forgets every picked file, and nothing else")
    func pickedFileGrantsAreForgotten() throws {
        let defaults = try #require(suites.make())
        for key in MaintenanceTools.pickedFileBookmarkKeys {
            defaults.set(Data([1]), forKey: key)
        }
        defaults.set(true, forKey: "RememberSearchQuery")

        MaintenanceTools.removePickedFileGrants(from: defaults)
        for key in MaintenanceTools.pickedFileBookmarkKeys {
            #expect(defaults.object(forKey: key) == nil)
        }
        #expect(defaults.bool(forKey: "RememberSearchQuery"))
    }

    @Test("A failed command names itself and its exit status, with its output when there is any")
    func failureText() {
        let quiet = MaintenanceTools.ToolError.commandFailed("tccutil", 1, "  \n")
        let noisy = MaintenanceTools.ToolError.commandFailed("killall", 2, "\nNo matching processes\n")
        #expect(quiet.errorDescription == "tccutil failed with exit status 1.")
        #expect(noisy.errorDescription == "killall failed with exit status 2: No matching processes")
    }
}
