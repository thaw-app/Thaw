//
//  ProfileLayoutDiffTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// What applying a profile would change, and the preview that shows it.
@MainActor
@Suite("Profile layout diff")
struct ProfileLayoutDiffTests {
    private static func layout(
        order: [String: [String]],
        map: [String: String]? = nil,
        names: [String: String] = [:],
        useItemOrder: Bool = true
    ) -> MenuBarLayoutSnapshot {
        MenuBarLayoutSnapshot(
            savedSectionOrder: order,
            pinnedHiddenBundleIDs: [],
            pinnedAlwaysHiddenBundleIDs: [],
            customNames: names,
            itemSectionMap: map,
            itemOrder: useItemOrder ? order : nil
        )
    }

    @Test("A profile that only reorders items within their sections is not reported as identical")
    func reorderWithinSection() {
        let current = Self.layout(order: ["visible": ["com.a:A", "com.b:B", "com.c:C"], "hidden": ["com.d:D", "com.e:E"]])
        let profile = Self.layout(order: ["visible": ["com.c:C", "com.a:A", "com.b:B"], "hidden": ["com.d:D", "com.e:E"]])

        let diff = ProfileLayoutDiff.between(current: current, profile: profile)

        #expect(diff.moves.isEmpty)
        #expect(diff.reorderedSections == ["visible"])
        #expect(!diff.isEmpty)
    }

    @Test("Moved, missing and extra items don't count as a reorder of the items that stay")
    func reorderIgnoresOtherChanges() {
        let current = Self.layout(order: ["visible": ["com.a:A", "com.x:X", "com.b:B", "com.extra:E"]])
        let profile = Self.layout(order: [
            "visible": ["com.a:A", "com.gone:G", "com.b:B"],
            "hidden": ["com.x:X"],
        ])

        let diff = ProfileLayoutDiff.between(current: current, profile: profile)

        #expect(diff.reorderedSections.isEmpty)
        #expect(diff.moves.map(\.item.id) == ["com.x:X"])
    }

    @Test("The same order on both sides is still identical")
    func sameOrder() {
        let order = ["visible": ["com.a:A", "com.b:B"], "hidden": ["com.c:C"]]
        let diff = ProfileLayoutDiff.between(current: Self.layout(order: order), profile: Self.layout(order: order, useItemOrder: false))
        #expect(diff.reorderedSections.isEmpty)
        #expect(diff.isEmpty)
    }

    @Test("Items in another section move, missing ones are unavailable, extra ones unmentioned")
    func between() {
        let current = Self.layout(order: [
            "visible": ["com.a:A", "com.b:B"],
            "hidden": ["com.c:C", "com.extra:X"],
        ])
        let profile = Self.layout(
            order: [
                "visible": ["com.c:C"],
                "hidden": ["com.a:A", "com.gone:G"],
                "alwaysHidden": ["com.b:B"],
            ],
            names: ["com.a:A": "Alpha"]
        )

        let diff = ProfileLayoutDiff.between(current: current, profile: profile)

        #expect(diff.moves.map(\.item.id) == ["com.c:C", "com.a:A", "com.b:B"])
        #expect(diff.moves.map(\.to) == ["visible", "hidden", "alwaysHidden"])
        #expect(diff.moves.map(\.from) == ["hidden", "visible", "visible"])
        #expect(diff.moves[1].item.title == "Alpha", "the profile's custom name wins")
        #expect(diff.moves[1].id == "com.a:A")
        #expect(diff.unavailable.map(\.bundleID) == ["com.gone"])
        #expect(diff.unmentioned.map(\.title) == ["X"])
        #expect(!diff.isEmpty)
    }

    @Test("Identical layouts produce an empty diff, using the per-item map when present")
    func identical() {
        let order = ["visible": ["com.a:A"], "hidden": ["bare.bundle"]]
        let current = Self.layout(order: order, map: ["com.a:A": "visible", "bare.bundle": "hidden"])
        let profile = Self.layout(order: order, useItemOrder: false)
        let diff = ProfileLayoutDiff.between(current: current, profile: profile)
        #expect(diff.isEmpty)
        #expect(diff.unmentioned.isEmpty)
    }

    @Test("A spacing relaunch alone makes the diff non-empty")
    func spacingAloneCounts() {
        var diff = ProfileLayoutDiff()
        #expect(diff.isEmpty)
        diff.relaunchingSpacingOffset = 2
        #expect(!diff.isEmpty)
    }

    @Test("Setting changes compare encoded fields and name them readably")
    func settingChanges() {
        var profile = GeneralSettingsSnapshot.defaults
        profile.showOnHover.toggle()
        profile.tempShowInterval = 99
        let changes = ProfileLayoutDiff.settingChanges(current: GeneralSettingsSnapshot.defaults, profile: profile)
        #expect(changes.map(\.key) == ["showOnHover", "tempShowInterval"])
        #expect(changes.map(\.label) == ["Show on hover", "Temp show interval"])
        #expect(changes.first?.id == "showOnHover")
        #expect(ProfileLayoutDiff.settingChanges(current: profile, profile: profile).isEmpty)
    }

    @Test("A field only one side has counts as a change, and non-objects compare as nothing")
    func oneSidedFields() {
        struct Left: Encodable { let a = 1 }
        struct Right: Encodable { let a = 1; let bOnly = true }
        #expect(ProfileLayoutDiff.settingChanges(current: Left(), profile: Right()).map(\.label) == ["B only"])
        #expect(ProfileLayoutDiff.settingChanges(current: [1, 2], profile: [3]).isEmpty)
    }

    @Test("Preview sections fall back to the saved order and parse bare bundle IDs")
    func previewSections() {
        let layout = Self.layout(order: ["hidden": ["com.app", "com.b:Title"]], names: ["com.b:Title": "Bee"], useItemOrder: false)
        let sections = ProfilePreviewModel.sections(for: layout)
        #expect(sections.map(\.key) == ["visible", "hidden", "alwaysHidden"])
        #expect(sections[0].items.isEmpty)
        #expect(sections[1].items.map(\.title) == ["com.app", "Bee"])
        #expect(sections[1].items.map(\.bundleID) == ["com.app", "com.b"])
        let split = ProfilePreviewModel.split("ns:a:b")
        #expect(split.namespace == "ns")
        #expect(split.title == "a:b")
    }
}

/// The profile preview drawn off screen.
@MainActor
@Suite("Profile preview view", .serialized)
struct ProfilePreviewViewTests {
    private static func profile() throws -> Profile {
        var profile = try JSONDecoder().decode(Profile.self, from: Data(#"{"name": "Preview"}"#.utf8))
        profile.menuBarLayout.itemOrder = [
            "visible": (0 ..< 15).map { "com.apple.finder:Item\($0)" },
            "hidden": ["com.unknown.app:Thing"],
        ]
        profile.generalSettings.showOnHover = true
        profile.generalSettings.showOnScroll = true
        return profile
    }

    private func height(_ view: some View) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: 420))
        host.frame = CGRect(x: 0, y: 0, width: 420, height: 800)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test("A diff with changes takes more room than an empty one, and no diff takes the least")
    func diffChangesHeight() throws {
        let profile = try Self.profile()
        var busy = ProfileLayoutDiff()
        let item = ProfileLayoutDiff.Item(id: "com.a:A", bundleID: "com.a", title: "A")
        busy.moves = Array(repeating: ProfileLayoutDiff.Move(item: item, from: "visible", to: "hidden"), count: 8)
        busy.unavailable = [item]
        busy.unmentioned = [item]
        busy.settingChanges = [ProfileLayoutDiff.SettingChange(key: "showOnHover", label: "Show on hover")]
        busy.relaunchingSpacingOffset = 3

        let none = height(ProfilePreviewView(profile: profile, diff: nil))
        let empty = height(ProfilePreviewView(profile: profile, diff: ProfileLayoutDiff()))
        let full = height(ProfilePreviewView(profile: profile, diff: busy))
        let inline = height(ProfilePreviewView(profile: profile, diff: nil, isInline: true))

        #expect(empty > none)
        #expect(full > empty)
        #expect(inline < none, "inline drops the name and the padding")
    }
}
