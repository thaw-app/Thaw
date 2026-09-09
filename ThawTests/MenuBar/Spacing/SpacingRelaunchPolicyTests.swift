//
//  SpacingRelaunchPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers the relaunch triage added for #1070.
///
/// The spacing wave has to restart status item owners for a new
/// NSStatusItemSpacing to show up right away, but a launch-constrained
/// system binary that no LaunchAgent claims cannot be brought back once it
/// is down: the respawn is SIGKILLed by AMFI and the item is gone until
/// reboot. Those must never be terminated in the first place.
@Suite("Spacing relaunch policy")
struct SpacingRelaunchPolicyTests {
    private func strategy(
        executable: String?,
        bundle: String?,
        bundleIdentifier: String? = "com.example.App",
        launchdLabel: String? = nil
    ) -> SpacingRelaunchStrategy {
        SpacingRelaunchPolicy.strategy(
            executableURL: executable.map { URL(fileURLWithPath: $0) },
            bundleURL: bundle.map { URL(fileURLWithPath: $0) },
            bundleIdentifier: bundleIdentifier,
            launchdLabel: launchdLabel
        )
    }

    @Test("An ordinary app is quit and launched back")
    func ordinaryAppIsRelaunched() {
        let result = strategy(
            executable: "/Applications/Notion.app/Contents/MacOS/Notion",
            bundle: "/Applications/Notion.app",
            bundleIdentifier: "notion.id"
        )
        #expect(
            result == .terminateAndLaunch(
                bundleURL: URL(fileURLWithPath: "/Applications/Notion.app")
            )
        )
    }

    @Test("An app in the user's home is quit and launched back")
    func userInstalledAppIsRelaunched() {
        let result = strategy(
            executable: "/Users/someone/Applications/Tool.app/Contents/MacOS/Tool",
            bundle: "/Users/someone/Applications/Tool.app"
        )
        #expect(
            result == .terminateAndLaunch(
                bundleURL: URL(fileURLWithPath: "/Users/someone/Applications/Tool.app")
            )
        )
    }

    /// The label wins even though the binary is system-owned: a kickstart
    /// is exactly how a constrained agent is meant to be restarted.
    @Test("An indexed LaunchAgent is kickstarted")
    func launchAgentIsKickstarted() {
        let result = strategy(
            executable: "/System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight",
            bundle: "/System/Library/CoreServices/Spotlight.app",
            bundleIdentifier: "com.apple.Spotlight",
            launchdLabel: "com.apple.Spotlight"
        )
        #expect(result == .launchdKickstart(label: "com.apple.Spotlight"))
    }

    /// The #1070 regression: no label, system binary, so the only safe
    /// move is to not touch it.
    @Test("An unclaimed system binary is left running")
    func unclaimedSystemBinaryIsLeftRunning() {
        let result = strategy(
            executable: "/System/Library/CoreServices/TextInputMenuAgent.app/Contents/MacOS/TextInputMenuAgent",
            bundle: "/System/Library/CoreServices/TextInputMenuAgent.app",
            bundleIdentifier: "com.apple.TextInputMenuAgent"
        )
        #expect(result == .leaveRunning(reason: .systemOwnedExecutable))
    }

    @Test(
        "Every system path prefix is left running",
        arguments: [
            "/System/Applications/Music.app/Contents/MacOS/Music",
            "/usr/libexec/AirPlayUIAgent",
            "/bin/sh",
            "/sbin/launchd",
            "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/MacOS/XProtect",
        ]
    )
    func systemPrefixesAreLeftRunning(path: String) {
        #expect(
            strategy(executable: path, bundle: path)
                == .leaveRunning(reason: .systemOwnedExecutable)
        )
    }

    /// A helper can report a bundle outside /System while executing from
    /// inside it, or the reverse. Either spelling makes the spawn
    /// constrained, so either one is enough to skip it.
    @Test("A system executable in a non-system bundle is left running")
    func systemExecutableInForeignBundleIsLeftRunning() {
        #expect(
            strategy(
                executable: "/System/Library/CoreServices/Helper.app/Contents/MacOS/Helper",
                bundle: "/Applications/Wrapper.app"
            ) == .leaveRunning(reason: .systemOwnedExecutable)
        )
        #expect(
            strategy(
                executable: "/Applications/Wrapper.app/Contents/MacOS/Helper",
                bundle: "/System/Library/CoreServices/Helper.app"
            ) == .leaveRunning(reason: .systemOwnedExecutable)
        )
    }

    @Test("A process with no bundle is left running")
    func bundlelessProcessIsLeftRunning() {
        #expect(
            strategy(executable: "/opt/homebrew/bin/agent", bundle: nil)
                == .leaveRunning(reason: .noRelaunchableBundle)
        )
    }

    @Test("A process with no bundle identifier is left running")
    func identifierlessProcessIsLeftRunning() {
        #expect(
            strategy(
                executable: "/Applications/Tool.app/Contents/MacOS/Tool",
                bundle: "/Applications/Tool.app",
                bundleIdentifier: nil
            ) == .leaveRunning(reason: .noRelaunchableBundle)
        )
        #expect(
            strategy(
                executable: "/Applications/Tool.app/Contents/MacOS/Tool",
                bundle: "/Applications/Tool.app",
                bundleIdentifier: ""
            ) == .leaveRunning(reason: .noRelaunchableBundle)
        )
    }

    /// /Systems and /usrlocal are not /System/ and /usr/; the
    /// prefixes carry their trailing separator so a same-prefixed name at
    /// the root can't be mistaken for a system location.
    @Test(
        "A lookalike path is not treated as system-owned",
        arguments: [
            "/Systems/Tool.app",
            "/usrlocal/bin/tool",
            "/Library/Application Support/Tool.app",
        ]
    )
    func lookalikePathsAreNotSystemOwned(path: String) {
        #expect(!SpacingRelaunchPolicy.isSystemOwned(URL(fileURLWithPath: path)))
    }

    @Test("A missing URL is not system-owned on its own")
    func missingURLIsNotSystemOwned() {
        #expect(!SpacingRelaunchPolicy.isSystemOwned(nil))
    }
}
