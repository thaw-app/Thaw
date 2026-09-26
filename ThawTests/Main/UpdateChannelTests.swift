//
//  UpdateChannelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins the channel split that separated alpha from beta.
///
/// Alpha and beta are separate opt-ins on one feed. Sparkle always allows
/// the default channel, so stable releases lose only because Sparkle offers
/// the newest allowed item and 3.x outranks 2.x.
///
/// Serialized: the migration writes through the process-wide `Defaults.store`.
@Suite("Update channels", .serialized)
struct UpdateChannelTests {
    /// Sparkle offers an item with no `sparkle:channel` to every subscriber,
    /// so stable is the absence of an opt-in rather than a channel of its own.
    @Test("Stable subscribes to no explicit channel")
    func stableAllowsNoChannels() {
        #expect(UpdateChannel.stable.allowedSparkleChannels.isEmpty)
    }

    /// Beta must not pull alpha in with it.
    @Test("Beta takes beta without alpha")
    func betaExcludesAlpha() {
        #expect(UpdateChannel.beta.allowedSparkleChannels == ["beta"])
    }

    /// On a macOS this build supports, beta's tags don't change.
    @Test("Beta stays beta-only on a supported macOS", arguments: [25, 26])
    func betaStaysBetaOnSupportedVersions(majorVersion: Int) {
        #expect(UpdateChannel.beta.allowedSparkleChannels(on: Self.version(majorVersion)) == ["beta"])
    }

    /// On an unsupported macOS every 2.x beta is unrunnable, so beta also
    /// takes the rewrite's alpha builds. The other channels are unchanged.
    @Test("Beta takes alpha too on an unsupported macOS", arguments: [27, 28])
    func betaTakesAlphaOnUnsupportedVersions(majorVersion: Int) {
        let version = Self.version(majorVersion)
        #expect(UpdateChannel.beta.allowedSparkleChannels(on: version) == ["beta", "alpha"])
        #expect(UpdateChannel.alpha.allowedSparkleChannels(on: version) == ["alpha"])
        #expect(UpdateChannel.stable.allowedSparkleChannels(on: version).isEmpty)
    }

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

    /// The alert points at alpha, so a system that sees it must be able to select alpha.
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

    /// Existing "Development" subscribers opted in before the rewrite existed,
    /// so they land on beta, not alpha.
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

    /// Otherwise choosing alpha would read back as beta.
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
