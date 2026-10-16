//
//  DegradedIdentityReadingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers ``LayoutSolver/liveIdentitiesAreDegraded(_:)``, which keeps a bar-wide
/// `kCGWindowName` degradation out of the cache.
///
/// A log read the hidden section as `com.rogueamoeba.soundsource:com.rogueamoeba.soundsource`
/// and ten more like it, Thaw's control item included, minutes after a normal
/// reading (#881). Caching it saves the bar under a second set of identifiers,
/// and each flip back triggers a re-sort, bulk apply, and captured cursor.
///
/// A false positive costs one skipped cycle, so most tests pin what must not trip.
@Suite("Degraded identity reading")
struct DegradedIdentityReadingTests {
    private func identities(_ pairs: [(String, String)]) -> [(namespace: String, title: String)] {
        pairs.map { (namespace: $0.0, title: $0.1) }
    }

    /// Eleven entries from the #881 log, verbatim.
    @Test("A bar-wide degraded reading is caught")
    func catchesBarWideDegradation() {
        let degraded = identities([
            ("com.apphousekitchen.aldente-pro", "com.apphousekitchen.aldente-pro"),
            ("com.rogueamoeba.soundsource", "com.rogueamoeba.soundsource"),
            ("com.rogueamoeba.soundsource", "com.rogueamoeba.soundsource"),
            ("com.steipete.codexbar", "com.steipete.codexbar"),
            ("com.tunabellysoftware.tgpro", "com.tunabellysoftware.tgpro"),
            ("eu.exelban.Stats", "eu.exelban.Stats"),
            ("leits.MeetingBar", "leits.MeetingBar"),
        ])
        #expect(LayoutSolver.liveIdentitiesAreDegraded(degraded))
    }

    /// Thaw titles its items `Thaw.ControlItem.*`, so one titled with our bundle ID
    /// is always wrong, and it comes with unrecognizable dividers.
    @Test("Our own item titled with our bundle ID is enough on its own")
    func ownDegradedControlItemIsSufficient() {
        let own = Constants.bundleIdentifier
        let reading = identities([
            ("com.apple.controlcenter", "WiFi"),
            (own, own),
            ("us.zoom.xos", "Item-0"),
        ])
        #expect(LayoutSolver.liveIdentitiesAreDegraded(reading))
    }

    // MARK: - What must not trip it

    @Test("A healthy reading is not degraded")
    func healthyReadingPasses() {
        let own = Constants.bundleIdentifier
        let reading = identities([
            (own, "Thaw.ControlItem.Visible"),
            (own, "Thaw.ControlItem.Hidden"),
            ("com.apple.controlcenter", "WiFi"),
            ("com.apple.controlcenter", "Battery"),
            ("eu.exelban.Stats", "CPU_bar_chart"),
            ("com.steipete.codexbar", "codexbar-claude"),
            ("us.zoom.xos", "Item-0"),
        ])
        #expect(!LayoutSolver.liveIdentitiesAreDegraded(reading))
    }

    /// An app may title its window with its bundle ID; alone on a populated bar
    /// that proves nothing, and freezing the cache would strand the layout.
    @Test("A single self-titled item on a healthy bar is tolerated")
    func singleSelfTitledItemIsTolerated() {
        let reading = identities([
            ("com.example.selfnamed", "com.example.selfnamed"),
            ("com.apple.controlcenter", "WiFi"),
            ("com.apple.controlcenter", "Battery"),
            ("eu.exelban.Stats", "CPU_bar_chart"),
            ("us.zoom.xos", "Item-0"),
        ])
        #expect(!LayoutSolver.liveIdentitiesAreDegraded(reading))
    }

    /// Half of three is not evidence of anything.
    @Test("A short reading is never judged on proportion alone")
    func shortReadingIsNotJudged() {
        let reading = identities([
            ("com.example.selfnamed", "com.example.selfnamed"),
            ("com.apple.controlcenter", "WiFi"),
        ])
        #expect(!LayoutSolver.liveIdentitiesAreDegraded(reading))
    }

    /// An empty reading is the other guard's business, not this one's.
    @Test("An empty reading is not degraded")
    func emptyReadingPasses() {
        #expect(!LayoutSolver.liveIdentitiesAreDegraded([]))
    }

    /// A title that continues past the bundle ID still identifies the item, so only exact equality counts.
    @Test("Titles that merely begin with the namespace are not self-titled")
    func prefixTitlesAreNotSelfTitled() {
        let reading = identities([
            ("com.hegenberg.BetterTouchTool", "com.hegenberg.BetterTouchTool (449CF8DD)"),
            ("com.apple.TextInputMenuAgent", "com.apple.TextInputMenuAgent.Extra"),
            ("com.apple.menuextra", "com.apple.menuextra.TimeMachine"),
            ("com.example.app", "com.example.app2"),
        ])
        #expect(!LayoutSolver.liveIdentitiesAreDegraded(reading))
    }

    /// Unreadable titles are empty, and counting them would let an untitled bar read as degraded.
    @Test("Empty titles do not count as self-titled")
    func emptyTitlesDoNotCount() {
        let reading = identities([
            ("com.apple.controlcenter", ""),
            ("com.apple.controlcenter", ""),
            ("com.apple.controlcenter", ""),
            ("com.apple.controlcenter", ""),
        ])
        #expect(!LayoutSolver.liveIdentitiesAreDegraded(reading))
    }

    /// Nested helper namespaces are canonicalized but titles are not, so a degraded
    /// Little Snitch item never matches literally.
    @Test("A canonicalized helper namespace is still self-titled")
    func canonicalizedHelperNamespaceIsSelfTitled() {
        let reading = identities([
            ("at.obdev.littlesnitch", "at.obdev.littlesnitch.agent"),
            ("com.apple.controlcenter", "WiFi"),
            ("com.apple.controlcenter", "Battery"),
            ("eu.exelban.Stats", "eu.exelban.Stats"),
        ])
        #expect(LayoutSolver.liveIdentitiesAreDegraded(reading))
    }
}
