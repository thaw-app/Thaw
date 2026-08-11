//
//  DegradedIdentityReadingTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Covers ``LayoutSolver/liveIdentitiesAreDegraded(_:)``, the gate that stops a
/// bar-wide `kCGWindowName` degradation from reaching the cache.
///
/// #881's 12:38 log read the live hidden section as
/// `com.rogueamoeba.soundsource:com.rogueamoeba.soundsource` and ten more of
/// the same shape, Thaw's own control item among them, two minutes after the
/// same items had read normally. Caching that reading persists the whole bar
/// under a second set of identifiers, and every later flip between the two
/// spellings presents a bar's worth of late arrivals — a re-sort, a bulk apply,
/// posted moves, a captured cursor. The reporter's unenacted-move streak
/// reached nine.
///
/// The cost of a false positive is one skipped cache cycle, so these tests
/// mostly pin the cases that must *not* trip it.
@Suite("Degraded identity reading")
struct DegradedIdentityReadingTests {
    private func identities(_ pairs: [(String, String)]) -> [(namespace: String, title: String)] {
        pairs.map { (namespace: $0.0, title: $0.1) }
    }

    /// Eleven of #881's, verbatim, as the log listed them.
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

    /// The certain signal. Thaw titles its own items `Thaw.ControlItem.*`, so
    /// one in our namespace wearing our bundle identifier cannot be a correct
    /// reading — and it arrives with the dividers unrecognizable, which is why
    /// the same logs report the hidden control item missing.
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

    /// The ordinary bar.
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

    /// One app really may name its window after its own bundle identifier.
    /// Alone on a populated bar it proves nothing, and freezing the cache over
    /// it would strand the layout.
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

    /// That same app on a bar too small to judge. Half of three is not
    /// evidence of anything.
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

    /// A title that continues past the bundle identifier still identifies the
    /// item, so exact equality is the whole test.
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

    /// An item whose title could not be read at all is empty, not self-titled;
    /// counting it would let a bar of untitled items read as degraded.
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

    /// The namespace of a nested helper is canonicalized on the way in while
    /// the title is not, so the two halves of a degraded Little Snitch item
    /// never match literally.
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
