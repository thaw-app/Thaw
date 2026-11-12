//
//  ProfileGapsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw
import ThawUI

@Suite("Profile shortcuts merge")
struct ProfileHotkeyMergeTests {
    private let a = Data("a".utf8)
    private let b = Data("b".utf8)
    private let c = Data("c".utf8)

    @Test("A profile sets and clears the shortcuts it knew, and leaves newer actions alone")
    func knownActions() {
        let merged = ProfileHotkeyMerge.merged(
            current: ["old": a, "cleared": b, "newer": c],
            profile: ["old": b],
            knownActions: ["old", "cleared"]
        )
        #expect(merged == ["old": b, "newer": c])
    }

    @Test("An older profile only sets the shortcuts it stores")
    func olderProfile() {
        let merged = ProfileHotkeyMerge.merged(current: ["kept": a, "set": b], profile: ["set": c], knownActions: nil)
        #expect(merged == ["kept": a, "set": c])
    }
}

@Suite("Profile file compatibility")
struct ProfileFileCompatibilityTests {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func decode(_ json: String) throws -> Profile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Profile.self, from: Data(json.utf8))
    }

    private static func encode(_ profile: Profile) throws -> String {
        try String(decoding: encoder.encode(profile), as: UTF8.self)
    }

    @Test("A profile from an older build has no shortcut actions and no stored Always Hidden switch")
    func olderProfile() throws {
        let profile = try Self.decode(#"{"name": "Old", "advancedSettings": {"showMenuBarTooltips": true}}"#)
        #expect(profile.hotkeyActions == nil)
        #expect(!profile.storesAlwaysHiddenSection)
    }

    @Test("A profile that stores the switch says so, and rewrites keep the fact")
    func storedSwitch() throws {
        let profile = try Self.decode(
            #"{"name": "New", "storesAlwaysHiddenSection": true, "advancedSettings": {"enableAlwaysHiddenSection": false}, "hotkeyActions": ["a"]}"#
        )
        #expect(profile.storesAlwaysHiddenSection)
        #expect(profile.hotkeyActions == ["a"])
        let json = try Self.encode(profile)
        #expect(json.contains("hotkeyActions"))
        try Self.rewritesKeep(json: json, expected: true)
    }

    @Test("A profile from a released build, which holds the switch without saying it stores it, still only turns Always Hidden on")
    func releasedBuildProfileOnlyTurnsOn() throws {
        let profile = try Self.decode(#"{"name": "Released", "advancedSettings": {"enableAlwaysHiddenSection": false}}"#)
        #expect(!profile.storesAlwaysHiddenSection)

        var current = AdvancedSettingsSnapshot.defaults
        current.enableAlwaysHiddenSection = true
        let applied = profile.advancedSettings.merged(onto: current, storesAlwaysHiddenSection: profile.storesAlwaysHiddenSection)
        #expect(applied.enableAlwaysHiddenSection, "applying it leaves Always Hidden on, as released builds do")

        try Self.rewritesKeep(json: Self.encode(profile), expected: false)
    }

    @Test("A profile that says it stores the switch turns Always Hidden off")
    func markedProfileTurnsOff() throws {
        let profile = try Self.decode(#"{"name": "New", "storesAlwaysHiddenSection": true, "advancedSettings": {"enableAlwaysHiddenSection": false}}"#)
        var current = AdvancedSettingsSnapshot.defaults
        current.enableAlwaysHiddenSection = true
        let applied = profile.advancedSettings.merged(onto: current, storesAlwaysHiddenSection: profile.storesAlwaysHiddenSection)
        #expect(!applied.enableAlwaysHiddenSection)
    }

    @Test("A rewritten old profile still only turns Always Hidden on")
    func renamedOldProfileKeepsTheFact() throws {
        let profile = try Self.decode(#"{"name": "Old", "advancedSettings": {"showMenuBarTooltips": true}}"#)
        #expect(!profile.storesAlwaysHiddenSection)

        let json = try Self.encode(profile)
        try Self.rewritesKeep(json: json, expected: false)
    }

    /// Re-encoding a profile must not change whether its file stores the switch.
    private static func rewritesKeep(json: String, expected: Bool) throws {
        let reread = try Self.decode(json)
        #expect(reread.storesAlwaysHiddenSection == expected)
        // The advanced settings the rewritten file holds must not say otherwise.
        if expected {
            let data = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            let advanced = data?["advancedSettings"] as? [String: Any]
            #expect(advanced?["enableAlwaysHiddenSection"] != nil)
        }
    }

    @Test("An export from an older build, without apply shortcuts, still reads")
    func olderExport() throws {
        let bundle = try JSONDecoder().decode(
            ProfileExportBundle.self,
            from: Data(#"{"version": 1, "entries": [{"profile": {"name": "Old"}}]}"#.utf8)
        )
        #expect(bundle.entries.first?.applyShortcut == nil)
    }
}

@MainActor
@Suite("Profile export and apply shortcuts", .serialized, .scratchDefaults)
struct ProfileExportTests {
    private static func profile(named name: String) throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: Data(#"{"name": "\#(name)"}"#.utf8))
    }

    @Test("Export All names the profiles it couldn't read instead of dropping them silently")
    func unreadableProfiles() throws {
        let good = try Self.profile(named: "Good")
        let metadata = [
            ProfileMetadata(id: good.id, name: "Good", createdAt: .now, modifiedAt: .now),
            ProfileMetadata(id: UUID(), name: "Broken", createdAt: .now, modifiedAt: .now),
        ]
        let all = ProfileExportBuilder.all(metadata) { id in
            guard id == good.id else { throw CocoaError(.fileReadCorruptFile) }
            return good
        }
        #expect(all.bundle.entries.map(\.profile.name) == ["Good"])
        #expect(all.unreadableNames == ["Broken"])
    }

    @Test("An export carries the profile's apply shortcut")
    func exportCarriesShortcut() throws {
        let profile = try Self.profile(named: "P")
        let shortcut = Data("⌃⌥1".utf8)
        Defaults.set([profile.id.uuidString: shortcut], forKey: .profileHotkeys)
        let entry = ProfileExportBuilder.entry(for: profile, meta: nil)
        #expect(entry.applyShortcut == shortcut)
    }

    @Test("An imported shortcut is kept unless another profile already uses it")
    func adoptingShortcuts() {
        let shortcuts = ProfileApplyShortcuts()
        let first = UUID()
        let second = UUID()
        let shortcut = Data("⌃⌥1".utf8)
        #expect(shortcuts.adopt(shortcut, for: first))
        #expect(!shortcuts.adopt(shortcut, for: second), "one shortcut applies one profile")
        #expect(!shortcuts.adopt(nil, for: second))
        #expect(shortcuts.shortcut(for: first) == shortcut)
        #expect(shortcuts.shortcut(for: second) == nil)
    }

    @Test("Importing a file restores its apply shortcut and puts it on the profile's live hotkey")
    func importRestoresShortcut() throws {
        try ProfileTestDirectory.withManager(seeding: []) { manager, tmp in
            let combination = KeyCombination(key: KeyCode(rawValue: 0x6A), modifiers: [.command, .option, .control, .shift])
            let shortcut = try JSONEncoder().encode(combination)
            // With an AppState the import's publish runs the hotkey rebuild, as it does in the app.
            let appState = AppState() // the manager holds it weakly
            manager.appState = appState
            let bundle = try ProfileExportBundle(entries: [ProfileExportEntry(profile: Self.profile(named: "Imported"), applyShortcut: shortcut)])
            let file = tmp.appendingPathComponent("bundle.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(bundle).write(to: file)

            try manager.importProfile(from: file)

            let imported = try #require(manager.profiles.first { $0.name == "Imported" })
            #expect(ProfileApplyShortcuts().shortcut(for: imported.id) == shortcut)
            let hotkey = try #require(manager.profileHotkeys[imported.id], "the rebuild made a hotkey for the imported profile")
            defer { hotkey.keyCombination = nil }
            #expect(hotkey.keyCombination == combination, "and loaded the restored shortcut into it")
            #expect(manager.hotkeyProfileMap[ObjectIdentifier(hotkey)] == imported.id)
        }
    }

    @Test("The preview lists each part of the setup that differs, in order")
    func changedAreas() {
        let same = Data("x".utf8)
        let changes = ProfilePreviewChanges.changedAreas([
            .init(key: "area.appearance", label: "Appearance", current: same, profile: Data("y".utf8)),
            .init(key: "area.shortcuts", label: "Shortcuts", current: same, profile: same),
            .init(key: "area.names", label: "Item names", current: nil, profile: same),
        ])
        #expect(changes.map(\.label) == ["Appearance", "Item names"])
    }

    @Test("The preview builds its list from the app's state: a part that differs from the profile is listed, one that matches is not")
    func settingChangesFollowTheApp() throws {
        let appState = AppState()
        let profile = try Self.profile(named: "P")
        let labels = { ProfilePreviewChanges.settingChanges(of: profile, appState: appState).map(\.label) }
        let itemNames = String(localized: "Item names")

        Defaults.set([String: String](), forKey: .menuBarItemCustomNames)
        #expect(!labels().contains(itemNames), "the profile and the app both have no custom names")

        Defaults.set(["com.example.App": "Renamed"], forKey: .menuBarItemCustomNames)
        #expect(labels().contains(itemNames), "the app has a name the profile does not")
    }
}
