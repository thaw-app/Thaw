//
//  UpdateChannelTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins the channel split that separated alpha from beta.
///
/// A single `AllowsBetaUpdates` flag used to return `["alpha", "beta"]`
/// together, so there was no way to take release candidates without also
/// taking the rewrite. Alpha and beta are now separate opt-ins on the one
/// feed. Sparkle always includes the default channel in the allowed set, so
/// no `allowedChannels` value can keep stable releases away from a
/// subscriber; what keeps them from winning is that Sparkle offers the
/// newest allowed item, and 3.x outranks anything the 2.x line can carry.
///
/// Serialized and run against a scratch defaults suite: the migration reads
/// and writes real preference keys through the process-wide `Defaults.store`.
@Suite("Update channels", .serialized)
struct UpdateChannelTests {
    /// Sparkle offers an item with no `sparkle:channel` to every subscriber,
    /// so stable is the absence of an opt-in rather than a channel of its own.
    @Test("Stable subscribes to no explicit channel")
    func stableAllowsNoChannels() {
        #expect(UpdateChannel.stable.allowedSparkleChannels.isEmpty)
    }

    /// The point of the split: beta must not pull alpha in with it.
    @Test("Beta takes beta without alpha")
    func betaExcludesAlpha() {
        #expect(UpdateChannel.beta.allowedSparkleChannels == ["beta"])
    }

    /// The other half of the split: alpha must not pull beta in with it.
    /// Alpha is a parallel track, not a superset of the release candidates.
    @Test("Alpha takes alpha without beta")
    func alphaExcludesBeta() {
        #expect(UpdateChannel.alpha.allowedSparkleChannels == ["alpha"])
    }

    /// No channel overrides the feed: all three read the `SUFeedURL` from
    /// `Info.plist`, and the appcast's `sparkle:channel` tags do the sorting.
    @Test("Every channel reads the same feed")
    func noChannelOverridesTheFeed() {
        #expect(UpdateChannel.beta.allowedSparkleChannels
            .isDisjoint(with: UpdateChannel.alpha.allowedSparkleChannels))
    }

    // MARK: Availability

    /// The rewrite targets the macOS this build does not support, so the
    /// channel carrying it stays hidden until the user is on that macOS.
    @Test("Alpha is hidden before macOS 27", arguments: [25, 26])
    func alphaHiddenOnSupportedVersions(majorVersion: Int) {
        let cases = UpdateChannel.availableCases(on: Self.version(majorVersion))
        #expect(cases == [.stable, .beta])
        #expect(!UpdateChannel.alpha.isAvailable(on: Self.version(majorVersion)))
    }

    /// The threshold is shared with the compatibility warning, whose alert
    /// tells the user that support arrives through this channel.
    @Test("Alpha is offered from macOS 27 on", arguments: [27, 28])
    func alphaOfferedOnUnsupportedVersions(majorVersion: Int) {
        let cases = UpdateChannel.availableCases(on: Self.version(majorVersion))
        #expect(cases == [.stable, .beta, .alpha])
    }

    /// The warning and the channel have to move together: the alert points at
    /// alpha, so a system that sees the alert must be able to select it.
    @Test("The warning and the alpha gate share a threshold", arguments: [25, 26, 27, 28])
    func warningAndAlphaGateAgree(majorVersion: Int) {
        let version = Self.version(majorVersion)
        #expect(
            MacOSCompatibilityWarning.shouldShow(for: version)
                == UpdateChannel.alpha.isAvailable(on: version)
        )
    }

    /// Stable and beta are always selectable.
    @Test("The shipping app's channels are always available", arguments: [25, 26, 27, 28])
    func shippingChannelsAlwaysAvailable(majorVersion: Int) {
        #expect(UpdateChannel.stable.isAvailable(on: Self.version(majorVersion)))
        #expect(UpdateChannel.beta.isAvailable(on: Self.version(majorVersion)))
    }

    /// Selecting alpha and then returning to a supported macOS must not pin
    /// the user to a feed that will never offer them anything.
    @Test("A stored alpha is not honored on a supported macOS")
    func storedAlphaIsNotHonoredBeforeMacOS27() throws {
        try withScratchDefaults { suite in
            suite.set(UpdateChannel.alpha.rawValue, forKey: "UpdateChannel")
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(26)) == .beta)
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(27)) == .alpha)
        }
    }

    private static func version(_ majorVersion: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: majorVersion, minorVersion: 0, patchVersion: 0)
    }

    // MARK: Storage

    /// Fresh installs start on stable.
    @Test("No stored preference means stable")
    func absentPreferenceIsStable() throws {
        try withScratchDefaults { _ in
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(27)) == .stable)
        }
    }

    /// Existing "Development" subscribers land on beta, not alpha. Migrating
    /// them to alpha would push the rewrite onto people who opted into a
    /// setting that predated it.
    @Test("The superseded flag migrates to beta")
    func legacyFlagMigratesToBeta() throws {
        try withScratchDefaults { suite in
            suite.set(true, forKey: "AllowsBetaUpdates")
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(27)) == .beta)
        }
    }

    /// A stable user under the old flag stays stable.
    @Test("A false superseded flag stays stable")
    func legacyFlagOffStaysStable() throws {
        try withScratchDefaults { suite in
            suite.set(false, forKey: "AllowsBetaUpdates")
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(27)) == .stable)
        }
    }

    /// Once the user has picked a channel, the superseded flag no longer
    /// speaks for them — otherwise choosing alpha would read back as beta.
    @Test("An explicit channel wins over the superseded flag")
    func explicitChannelWinsOverLegacyFlag() throws {
        try withScratchDefaults { suite in
            suite.set(true, forKey: "AllowsBetaUpdates")
            suite.set(UpdateChannel.alpha.rawValue, forKey: "UpdateChannel")
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(27)) == .alpha)
        }
    }

    /// An unrecognized value (a downgrade from a build with more channels,
    /// or a hand-edited plist) falls back rather than trapping.
    @Test("An unknown stored channel falls back to the superseded flag")
    func unknownChannelFallsBack() throws {
        try withScratchDefaults { suite in
            suite.set(true, forKey: "AllowsBetaUpdates")
            suite.set("canary", forKey: "UpdateChannel")
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(27)) == .beta)
        }
    }

    /// Every channel round-trips through the stored raw value.
    @Test("Each channel round-trips", arguments: UpdateChannel.allCases)
    func channelRoundTrips(channel: UpdateChannel) throws {
        try withScratchDefaults { suite in
            suite.set(channel.rawValue, forKey: "UpdateChannel")
            #expect(UpdatesManager.storedUpdateChannel(on: Self.version(27)) == channel)
        }
    }
}
