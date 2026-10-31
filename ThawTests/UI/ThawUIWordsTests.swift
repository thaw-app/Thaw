//
//  ThawUIWordsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw
import ThawUI

/// What Thaw hands the shared package: its identity, its wiring, and the words
/// that must keep today's catalog keys.
@MainActor
@Suite("ThawUI wiring")
struct ThawUIWordsTests {
    @Test("Thaw's app info shows version 3's notes on every channel")
    func appInfo() {
        let info = ThawAppInfo.thaw
        #expect(info.displayName == Constants.displayName)
        #expect(info.version == Constants.versionString)
        #expect(info.changelogURL == Constants.changelogURL)
        #expect(info.releasesURL == Constants.releasesURL)
        #expect(info.shownMajorVersion == 3)
        #expect(info.showsChannels)
        #expect(info.cacheFolderName == nil, "the last fetched copy stays where earlier builds left it")
    }

    @Test("The HUD measures the menu bar the way the app does")
    func hudUsesTheAppsEstimate() throws {
        let screen = try #require(NSScreen.screens.first)
        // The app delegate sets this at launch, in the test host too.
        #expect(ThawHUD.menuBarHeight(screen) == screen.getMenuBarHeightEstimate())
    }

    @Test("Interpolated words keep their catalog keys")
    func interpolatedKeys() {
        #expect(AppUIZoomStrings.thaw.level(125).key == "Zoom: %lld%%")
        #expect(ThawGradientPickerStrings.thaw.stopName(2).key == "Color stop %lld")
        #expect(WhatsNewStrings.thaw.releaseTitle("3.0.0").key == "What’s new in %@")
        #expect(WhatsNewStrings.thaw.loadFailed("Thaw").key == "%@ couldn’t load the release notes.")
        #expect(AboutUpdateStrings.thaw.lastChecked("today").key == "Last checked %@")
        #expect(UpdateConsentStrings.thaw.title.key == "Keep %@ up to date?")
        #expect(AboutStrings.thaw.versionLabel("3", "1", "abc").key == "Version %@, build %@, commit %@")
    }

    @Test("A cached copy and an empty page say different things with fetching off")
    func fetchingOffWords() {
        #expect(WhatsNewStrings.thaw.fetchingOff.key != WhatsNewStrings.thaw.fetchingOffCached.key)
    }

    @Test("Each app supplied callout and channel has a name of its own")
    func namedCases() {
        let callouts = ChangelogDocument.Callout.Kind.allCases.map(\.localized.key)
        #expect(Set(callouts).count == callouts.count)
        let channels = UpdateChannel.allCases.map(\.localized.key)
        #expect(Set(channels).count == channels.count)
    }
}
