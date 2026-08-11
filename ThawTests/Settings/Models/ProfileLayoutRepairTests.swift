//
//  ProfileLayoutRepairTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Covers ``ProfileManager/repairPersistedLayouts()``, the pass that applies
/// the saved-order pruning rules to the profile JSON on disk.
///
/// ``MenuBarItemManager`` has always repaired the saved section order it loads
/// and written the result back, so a widened pruning rule reaches that store on
/// the next launch. Profiles were only ever pruned on the way out, through
/// `resolvedItemOrder`, which left the damage in the file and let it seed the
/// in-memory saved order again at every startup.
///
/// Every assertion reads through a *second* `ProfileManager` over the same
/// directory, so a repair that only happened in memory fails the test.
@MainActor
@Suite("Profile layout repair", .serialized)
struct ProfileLayoutRepairTests {
    /// The shape #927's reporter carried: Control Center's WiFi item saved
    /// under Thaw's own namespace, six WindowServer clones, and the genuine
    /// items alongside them.
    @Test("A damaged profile is pruned on disk")
    func repairsDamagedProfileOnDisk() throws {
        let own = Constants.bundleIdentifier
        let keeper = "com.hegenberg.BetterTouchTool:BetterTouchTool"
        let clone = "info.marcel-dierkes.KeepingYouAwake:System Status Item Clone:1"

        var profile = makeProfile(named: "Damaged")
        profile.menuBarLayout.itemOrder = [
            "visible": ["\(own):WiFi", "com.apple.controlcenter:WiFi", clone],
            "hidden": [keeper],
        ]

        try withTemporaryDirectory { tmp in
            try seedManifest(with: [profile], into: tmp)

            let repaired = ProfileManager(profilesDirectory: tmp).repairPersistedLayouts()
            #expect(repaired == 1)

            let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: profile.id)
            let order = reloaded.menuBarLayout.itemOrder
            #expect(order?["visible"] == ["com.apple.controlcenter:WiFi"])
            #expect(order?["hidden"] == [keeper])
        }
    }

    /// The map is a second spelling of the same layout, and
    /// `resolvedItemSectionMap` hands it back verbatim when present. An entry
    /// pruned from the order but left in the map would still be planned
    /// against.
    @Test("The section map is filtered to the surviving identifiers")
    func filtersSectionMapToSurvivors() throws {
        let own = Constants.bundleIdentifier
        let keeper = "us.zoom.xos:Item-0"

        var profile = makeProfile(named: "Mapped")
        profile.menuBarLayout.itemOrder = ["visible": ["\(own):WiFi", keeper]]
        profile.menuBarLayout.itemSectionMap = ["\(own):WiFi": "visible", keeper: "visible"]

        try withTemporaryDirectory { tmp in
            try seedManifest(with: [profile], into: tmp)
            ProfileManager(profilesDirectory: tmp).repairPersistedLayouts()

            let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: profile.id)
            #expect(reloaded.menuBarLayout.itemSectionMap == [keeper: "visible"])
        }
    }

    /// Profiles written before `itemOrder` existed carry the layout in
    /// `savedSectionOrder`, and that copy has to be repaired too.
    @Test("A legacy profile without itemOrder is repaired through savedSectionOrder")
    func repairsLegacyProfile() throws {
        let own = Constants.bundleIdentifier
        let keeper = "us.zoom.xos:Item-0"
        let profile = makeProfile(
            named: "Legacy",
            savedSectionOrder: ["visible": ["\(own):WiFi", keeper]]
        )

        try withTemporaryDirectory { tmp in
            try seedManifest(with: [profile], into: tmp)
            #expect(ProfileManager(profilesDirectory: tmp).repairPersistedLayouts() == 1)

            let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: profile.id)
            #expect(reloaded.menuBarLayout.savedSectionOrder["visible"] == [keeper])
            #expect(reloaded.menuBarLayout.itemOrder == nil)
        }
    }

    /// The idempotence property. A clean profile must not be rewritten, so the
    /// pass cannot churn `modifiedAt` or the file's bytes on every build.
    @Test("A clean profile is left untouched")
    func leavesCleanProfileAlone() throws {
        var profile = makeProfile(named: "Clean")
        profile.menuBarLayout.itemOrder = [
            "visible": ["com.apple.controlcenter:WiFi"],
            "hidden": ["us.zoom.xos:Item-0"],
        ]

        try withTemporaryDirectory { tmp in
            try seedManifest(with: [profile], into: tmp)
            let url = tmp.appendingPathComponent("\(profile.id.uuidString).json")
            let before = try Data(contentsOf: url)

            #expect(ProfileManager(profilesDirectory: tmp).repairPersistedLayouts() == 0)
            #expect(try Data(contentsOf: url) == before)
        }
    }

    /// A profile we cannot read is not a profile we should overwrite. The
    /// damaged sibling still gets repaired.
    @Test("An undecodable profile is skipped without blocking the others")
    func skipsUndecodableProfile() throws {
        let own = Constants.bundleIdentifier
        let broken = makeProfile(named: "Broken")
        var damaged = makeProfile(named: "Damaged")
        damaged.menuBarLayout.itemOrder = ["visible": ["\(own):WiFi", "us.zoom.xos:Item-0"]]

        try withTemporaryDirectory { tmp in
            try seedManifest(with: [broken, damaged], into: tmp)

            let brokenURL = tmp.appendingPathComponent("\(broken.id.uuidString).json")
            try Data("{ not a profile".utf8).write(to: brokenURL)

            #expect(ProfileManager(profilesDirectory: tmp).repairPersistedLayouts() == 1)

            let reloaded = try ProfileManager(profilesDirectory: tmp).loadProfile(id: damaged.id)
            #expect(reloaded.menuBarLayout.itemOrder?["visible"] == ["us.zoom.xos:Item-0"])
            #expect(try Data(contentsOf: brokenURL) == Data("{ not a profile".utf8))
        }
    }

    // MARK: - Helpers

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try body(tmp)
    }
}
