//
//  UpdatesManagerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Pins the promise the macOS compatibility alert makes.
///
/// The alert tells the user that a build for their macOS arrives through the
/// alpha channel, then starts a check for it. Sparkle says nothing when a
/// background check finds nothing, so the promise is tracked across the check
/// and answered with the releases page when the feed comes back empty. These
/// tests stand in for the check: they drive the outcomes Sparkle would report.
///
/// Serialized and run against a scratch defaults suite, since subscribing to a
/// channel writes real preference keys through the process-wide
/// `Defaults.store`.
@MainActor
@Suite("Compatibility update check", .serialized)
struct UpdatesManagerTests {
    /// Collects the URLs the manager would have handed to the browser.
    private func manager(opened: @escaping @MainActor (URL) -> Void) -> UpdatesManager {
        let manager = UpdatesManager()
        manager.openURL = opened
        return manager
    }

    /// Read back through ``UpdatesManager/storedUpdateChannel(on:)`` rather
    /// than `updateChannel`, whose getter withholds alpha from a system that
    /// still has a shipping build to run. The alert only appears past that
    /// line, but the machine running the tests need not be.
    @Test("Accepting the alert subscribes to alpha")
    func acceptingTheAlertSubscribesToAlpha() throws {
        try withScratchDefaults { _ in
            let manager = manager { _ in }
            manager.checkForAlphaUpdateAfterCompatibilityWarning()
            let unsupported = OperatingSystemVersion(
                majorVersion: MacOSCompatibilityWarning.firstUnsupportedMajorVersion,
                minorVersion: 0,
                patchVersion: 0
            )
            #expect(UpdatesManager.storedUpdateChannel(on: unsupported) == .alpha)
        }
    }

    /// A feed with no alpha item is the state of the world until the rewrite
    /// publishes one, so the fallback is the path most users take.
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

    /// Scheduled checks the user never asked for keep ending, and none of them
    /// owes anyone a browser window.
    @Test("A check nobody started opens nothing")
    func unrequestedCheckOpensNothing() throws {
        try withScratchDefaults { _ in
            var opened: [URL] = []
            let manager = manager { opened.append($0) }
            manager.resolveCompatibilityCheckWithReleasesPage()
            #expect(opened.isEmpty)
        }
    }

    /// The alert's check is shown as soon as it lands. Deferring it to a
    /// notification would answer the user's click with silence whenever they
    /// have not granted notifications.
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

    /// The update window is the answer, so the notification is dropped and the
    /// promise is closed with it: a later empty check belongs to someone else.
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

    /// Drives the delegate callbacks Sparkle itself calls, rather than the
    /// helpers behind them, so the wiring between the two is covered too. The
    /// updater is built with `startingUpdater: false`, so it schedules
    /// nothing and reaches no network.
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

    /// What Sparkle is told to accept comes from the stored channel, so the
    /// picker in Settings reaches the updater.
    @Test("The allowed channels follow the stored channel")
    func allowedChannelsFollowStoredChannel() throws {
        try withScratchDefaults { store in
            let manager = manager { _ in }
            store.set(UpdateChannel.beta.rawValue, forKey: "UpdateChannel")
            #expect(manager.allowedChannels(for: manager.updater) == ["beta"])
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
