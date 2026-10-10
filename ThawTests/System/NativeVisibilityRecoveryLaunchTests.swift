//
//  NativeVisibilityRecoveryLaunchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The rules that decide whether a recovery launch may touch Control Center's
/// app list: it was asked for, and no other menu bar manager is running.
@MainActor
@Suite("Native visibility recovery launch")
struct NativeVisibilityRecoveryLaunchTests {
    private typealias Launch = NativeVisibilityRecoveryLaunch
    private typealias RecoveryError = NativeVisibilityRecoveryModel.RecoveryError

    private func app(
        _ bundle: String?,
        pid: pid_t,
        name: String? = nil,
        terminated: Bool = false
    ) -> Launch.RunningApplication {
        Launch.RunningApplication(
            processIdentifier: pid,
            isTerminated: terminated,
            bundleIdentifier: bundle,
            localizedName: name
        )
    }

    @Test("Recovery is requested only by its own launch argument")
    func requestIsTheLaunchArgument() {
        #expect(Launch.isRequested(in: ["/Applications/Thaw.app/Contents/MacOS/Thaw", "--recover-menu-bar-visibility"]))
        #expect(!Launch.isRequested(in: ["/Applications/Thaw.app/Contents/MacOS/Thaw"]))
        #expect(!Launch.isRequested(in: ["Thaw", "--recover-menu-bar-visibility=1"]))
        #expect(!Launch.isRequested(in: []))
        #expect(!Launch.isRequested, "The test host was not launched for recovery")
    }

    @Test("Other copies of Thaw and Bartender conflict, by name")
    func otherManagersConflict() {
        let conflicts = Launch.conflictingApplications(
            among: [
                app("com.stonerl.Thaw", pid: 10, name: "Thaw"),
                app("com.stonerl.Thaw.debug", pid: 11, name: "Thaw Debug"),
                app("com.surteesstudios.Bartender", pid: 12, name: "Bartender 6"),
                app("com.apple.finder", pid: 13, name: "Finder"),
                app(nil, pid: 14, name: "Nameless"),
            ],
            ownProcessIdentifier: 1,
            ownBundleIdentifier: nil
        )
        #expect(conflicts == ["Thaw", "Thaw Debug", "Bartender 6"])
    }

    @Test("The recovery instance does not conflict with itself, but its twin does")
    func ownProcessIsNotAConflict() {
        let conflicts = Launch.conflictingApplications(
            among: [
                app("com.stonerl.Thaw", pid: 20, name: "Recovery"),
                app("com.stonerl.Thaw", pid: 21, name: "Normal"),
            ],
            ownProcessIdentifier: 20,
            ownBundleIdentifier: "com.stonerl.Thaw"
        )
        #expect(conflicts == ["Normal"])
    }

    @Test("A build under another bundle identifier conflicts with its own second copy")
    func ownBundleIdentifierIsWatched() {
        let fork = app("com.example.fork.Thaw", pid: 31, name: nil)
        #expect(Launch.conflictingApplications(
            among: [fork],
            ownProcessIdentifier: 30,
            ownBundleIdentifier: "com.example.fork.Thaw"
        ) == ["com.example.fork.Thaw"], "An app without a name is listed by bundle identifier")
        #expect(Launch.conflictingApplications(
            among: [fork],
            ownProcessIdentifier: 30,
            ownBundleIdentifier: "com.stonerl.Thaw"
        ).isEmpty)
    }

    @Test("An app that has already quit is not a conflict")
    func terminatedAppsAreIgnored() {
        let conflicts = Launch.conflictingApplications(
            among: [app("com.surteesstudios.Bartender", pid: 40, name: "Bartender", terminated: true)],
            ownProcessIdentifier: 1,
            ownBundleIdentifier: nil
        )
        #expect(conflicts.isEmpty)
    }

    @Test("The live conflict list never names this process")
    func liveConflictsExcludeThisProcess() {
        let own = NSRunningApplication.current
        let expected = Launch.conflictingApplications(
            among: NSWorkspace.shared.runningApplications
                .filter { $0.processIdentifier != own.processIdentifier }
                .map { app($0.bundleIdentifier, pid: $0.processIdentifier, name: $0.localizedName, terminated: $0.isTerminated) },
            ownProcessIdentifier: own.processIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
        #expect(Launch.conflictingApplications().sorted() == expected.sorted())
    }

    @Test("Exclusive access is refused on a normal launch, whatever else is running")
    func normalLaunchIsRefused() {
        #expect(throws: RecoveryError.normalLaunch) {
            try Launch.ensureExclusiveAccess(isRequested: false, conflictingApplications: [])
        }
        #expect(throws: RecoveryError.normalLaunch) {
            try Launch.ensureExclusiveAccess(isRequested: false, conflictingApplications: ["Bartender"])
        }
    }

    @Test("A recovery launch is refused while another manager runs, and allowed alone")
    func recoveryLaunchNeedsToBeAlone() throws {
        #expect(throws: RecoveryError.otherManagerRunning) {
            try Launch.ensureExclusiveAccess(isRequested: true, conflictingApplications: ["Thaw"])
        }
        try Launch.ensureExclusiveAccess(isRequested: true, conflictingApplications: [])
    }

    @Test("An app is named after its bundle on disk, or by identifier when not installed")
    func displayNameComesFromTheBundle() {
        #expect(Launch.displayName(
            forBundleID: "com.example.app",
            applicationURL: URL(fileURLWithPath: "/Applications/Utilities/Example App.app")
        ) == "Example App")
        #expect(Launch.displayName(forBundleID: "com.example.app", applicationURL: nil) == "com.example.app")
    }
}
