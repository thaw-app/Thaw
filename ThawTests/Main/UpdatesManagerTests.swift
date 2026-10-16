//
//  UpdatesManagerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins the promise the macOS compatibility alert makes.
///
/// The alert starts an alpha check. Sparkle stays silent when a background
/// check finds nothing, so an empty feed opens the releases page instead.
///
/// Serialized: subscribing writes through the process-wide `Defaults.store`.
@MainActor
@Suite("Compatibility update check", .serialized)
struct UpdatesManagerTests {
    /// Collects the URLs the manager would have handed to the browser.
    private func manager(opened: @escaping @MainActor (URL) -> Void) -> UpdatesManager {
        let manager = UpdatesManager()
        manager.openURL = opened
        return manager
    }

    /// Read via ``UpdatesManager/storedUpdateChannel(on:)`` because the
    /// `updateChannel` getter withholds alpha on a supported macOS.
    @Test("Accepting the alert subscribes to beta")
    func acceptingTheAlertSubscribesToBeta() throws {
        try withScratchDefaults { _ in
            let manager = manager { _ in }
            manager.checkForBetaUpdateAfterCompatibilityWarning()
            let unsupported = OperatingSystemVersion(
                majorVersion: MacOSCompatibilityWarning.firstUnsupportedMajorVersion,
                minorVersion: 0,
                patchVersion: 0
            )
            #expect(UpdatesManager.storedUpdateChannel(on: unsupported) == .beta)
        }
    }

    /// Until the rewrite publishes an alpha item, most users take this path.
    @Test("A check that finds nothing opens the releases page")
    func emptyFeedOpensReleasesPage() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.beginCompatibilityCheck()
            manager.resolveCompatibilityCheckWithReleasesPage()
            #expect(opened == [Constants.releasesURL])
        }
    }

    /// Sparkle reports an empty check twice: `updaterDidNotFindUpdate` first,
    /// then an abort carrying `SUNoUpdateError`. The second must not reopen
    /// the page.
    @Test("The promise is answered once")
    func promiseIsAnsweredOnce() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.beginCompatibilityCheck()
            manager.resolveCompatibilityCheckWithReleasesPage()
            manager.resolveCompatibilityCheckWithReleasesPage()
            #expect(opened.count == 1)
        }
    }

    /// Scheduled checks never open a browser window.
    @Test("A check nobody started opens nothing")
    func unrequestedCheckOpensNothing() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.resolveCompatibilityCheckWithReleasesPage()
            #expect(opened.isEmpty)
        }
    }

    /// Deferring to a notification would be silent without notification permission.
    @Test("The alert's check is never deferred")
    func compatibilityCheckIsShownImmediately() throws {
        try withScratchDefaults { _ in
            let manager = manager { _ in }
            manager.beginCompatibilityCheck()
            #expect(manager.shouldShowScheduledUpdate(inImmediateFocus: false, appIsActive: false))
        }
    }

    @Test(
        "An ordinary scheduled update follows the app's focus",
        arguments: [(true, true, true), (false, true, false), (true, false, false), (false, false, false)]
    )
    func ordinaryScheduledUpdateFollowsFocus(immediateFocus: Bool, appIsActive: Bool, expected: Bool) throws {
        try withScratchDefaults { _ in
            let manager = manager { _ in }
            #expect(
                manager.shouldShowScheduledUpdate(
                    inImmediateFocus: immediateFocus,
                    appIsActive: appIsActive
                ) == expected
            )
        }
    }

    /// The update window is the answer, so the notification is dropped and
    /// the promise closed.
    @Test("A found update answers the promise without notifying")
    func foundUpdateAnswersWithoutNotifying() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.beginCompatibilityCheck()
            #expect(!manager.shouldNotifyAboutUpdate(userInitiated: false))

            manager.resolveCompatibilityCheckWithReleasesPage()
            #expect(opened.isEmpty)
        }
    }

    /// Drives Sparkle's own delegate callbacks to cover the wiring.
    /// `startingUpdater: false` keeps it off the network.
    @Test("Sparkle reporting an empty check opens the releases page")
    func sparkleEmptyCheckOpensReleasesPage() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.beginCompatibilityCheck()
            manager.updaterDidNotFindUpdate(manager.updater)
            #expect(opened == [Constants.releasesURL])
        }
    }

    /// An empty check ends twice: `updaterDidNotFindUpdate`, then an abort
    /// carrying `SUNoUpdateError`. Only the first ending answers.
    @Test("The abort that follows an empty check is not a second answer")
    func abortAfterEmptyCheckDoesNotReopen() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.beginCompatibilityCheck()
            manager.updaterDidNotFindUpdate(manager.updater)
            manager.updater(manager.updater, didAbortWithError: CocoaError(.fileNoSuchFile))
            #expect(opened.count == 1)
        }
    }

    /// A check that never reaches the feed still owes the user the page.
    @Test("An abort on its own answers the promise")
    func abortAloneAnswersThePromise() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.beginCompatibilityCheck()
            manager.updater(manager.updater, didAbortWithError: CocoaError(.fileNoSuchFile))
            #expect(opened == [Constants.releasesURL])
        }
    }

    /// The Settings picker must reach the updater. Beta's tags depend on the
    /// running macOS, so the expectation does too.
    @Test("The allowed channels follow the stored channel")
    func allowedChannelsFollowStoredChannel() throws {
        try withScratchDefaults { store in
            let manager = manager { _ in }
            store.set(UpdateChannel.beta.rawValue, forKey: "UpdateChannel")
            let running = ProcessInfo.processInfo.operatingSystemVersion
            #expect(manager.allowedChannels(for: manager.updater) == UpdateChannel.beta.allowedSparkleChannels(on: running))
            #expect(manager.allowedChannels(for: manager.updater).contains("beta"))
        }
    }

    @Test("An ordinary background update is still announced")
    func ordinaryBackgroundUpdateNotifies() throws {
        try withScratchDefaults { _ in
            let manager = manager { _ in }
            #expect(manager.shouldNotifyAboutUpdate(userInitiated: false))
        }
    }

    /// An update the user asked for is already on screen in front of them.
    @Test("A user-initiated update is not announced")
    func userInitiatedUpdateDoesNotNotify() throws {
        try withScratchDefaults { _ in
            let manager = manager { _ in }
            #expect(!manager.shouldNotifyAboutUpdate(userInitiated: true))
        }
    }
}
