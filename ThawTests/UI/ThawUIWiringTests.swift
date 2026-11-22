//
//  ThawUIWiringTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// What Thaw hands the shared package: its identity, its wiring, and the words that must keep today's catalog keys.
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

/// Reduce Motion removed fades too, though a short cross-fade is what it should keep.
@MainActor
@Suite("Reduce Motion")
struct ReduceMotionTests {
    @Test("Under Reduce Motion a fade keeps a quick ease-out; otherwise it keeps the animation it was given")
    func fadeKeepsAQuickFade() {
        #expect(AnyTransition.fadeAnimation(reduceMotion: true, animation: .spring) == ThawMotion.reducedFade)
        #expect(AnyTransition.fadeAnimation(reduceMotion: true, animation: nil) == ThawMotion.reducedFade)
        #expect(AnyTransition.fadeAnimation(reduceMotion: false, animation: .spring) == .spring)
        #expect(AnyTransition.fadeAnimation(reduceMotion: false, animation: nil) == nil)
    }

    @Test("Under Reduce Motion a transaction drops its movement but leaves transitions their own fades")
    func transactionDropsMovement() {
        var reduced = Transaction(animation: .spring)
        ReduceMotionFade.apply(to: &reduced, reduceMotion: true)
        #expect(reduced.animation == nil)
        #expect(!reduced.disablesAnimations)

        var kept = Transaction(animation: .spring)
        ReduceMotionFade.apply(to: &kept, reduceMotion: false)
        #expect(kept.animation == .spring)
    }
}

@Suite("Small UI types")
@MainActor
struct UISmallTypesTests {
    @Test("Every HUD placement has a picker label")
    func placementLabels() {
        let labels = ThawHUDPlacement.allCases.map(\.localized)
        #expect(labels.count == 3)
        #expect(labels == ["Top left", "Top center", "Top right"])
    }

    @Test("A unit with more than one member is a group")
    func unitIsGroup() {
        #expect(!LayoutEditorOrder.Unit(id: "a", memberIDs: ["a"]).isGroup)
        #expect(LayoutEditorOrder.Unit(id: "g", memberIDs: ["a", "b"]).isGroup)
    }
}
