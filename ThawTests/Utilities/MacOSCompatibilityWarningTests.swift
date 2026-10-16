//
//  MacOSCompatibilityWarningTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("macOS compatibility warning")
struct MacOSCompatibilityWarningTests {
    @Test("macOS 27 and later show the warning", arguments: [27, 28])
    func unsupportedVersionsShowWarning(majorVersion: Int) {
        #expect(MacOSCompatibilityWarning.shouldShow(for: version(majorVersion)))
    }

    @Test("macOS 26 and earlier do not show the warning", arguments: [25, 26])
    func supportedVersionsDoNotShowWarning(majorVersion: Int) {
        #expect(!MacOSCompatibilityWarning.shouldShow(for: version(majorVersion)))
    }

    @Test("A supported macOS is owed no prompt", arguments: [25, 26])
    func supportedVersionsHaveNoPrompt(majorVersion: Int) {
        #expect(MacOSCompatibilityWarning.prompt(for: version(majorVersion), canSubscribe: true) == nil)
    }

    /// The offer needs an updates manager to carry it out. Without one the
    /// user is still told, and still given somewhere to go.
    @Test("Without a manager the prompt sends the user to the releases page")
    func noManagerOffersPreviewBuilds() throws {
        let prompt = try #require(MacOSCompatibilityWarning.prompt(for: version(27), canSubscribe: false))
        #expect(prompt.action == .openReleasesPage)
        #expect(prompt.confirmButtonTitle == String(localized: "View Preview Builds"))
    }

    @Test("With a manager the prompt offers the beta channel")
    func managerOffersBetaChannel() throws {
        let prompt = try #require(MacOSCompatibilityWarning.prompt(for: version(27), canSubscribe: true))
        #expect(prompt.action == .subscribeToBeta)
        #expect(prompt.confirmButtonTitle == String(localized: "Switch to Beta Updates"))
    }

    /// The channel the alert switches to must reach the rewrite's builds on
    /// the macOS it warns about, whichever channel those were published on.
    @Test("The offered channel reaches the rewrite on an unsupported macOS")
    func offeredChannelReachesTheRewrite() throws {
        let unsupported = version(MacOSCompatibilityWarning.firstUnsupportedMajorVersion)
        let prompt = try #require(MacOSCompatibilityWarning.prompt(for: unsupported, canSubscribe: true))
        #expect(prompt.action == .subscribeToBeta)
        #expect(UpdateChannel.beta.allowedSparkleChannels(on: unsupported) == ["beta", "alpha"])
    }

    /// The warning fires on every release from the unsupported one onward, so
    /// a later macOS must not be told about the first one this build refused.
    @Test("The copy names the running macOS", arguments: [27, 28, 30])
    func copyNamesTheRunningRelease(majorVersion: Int) throws {
        let prompt = try #require(
            MacOSCompatibilityWarning.prompt(for: version(majorVersion), canSubscribe: true)
        )
        #expect(prompt.title.contains("\(majorVersion)"))
        #expect(prompt.message.contains("macOS \(majorVersion)"))
        #expect(!prompt.title.contains("macOS 26"))
    }

    private func version(_ majorVersion: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0)
    }
}
