//
//  ProfileGapsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

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
    private static func decode(_ json: String) throws -> Profile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Profile.self, from: Data(json.utf8))
    }

    @Test("A profile from an older build has no shortcut actions and no stored Always Hidden switch")
    func olderProfile() throws {
        let profile = try Self.decode(#"{"name": "Old", "advancedSettings": {"showMenuBarTooltips": true}}"#)
        #expect(profile.hotkeyActions == nil)
        #expect(!profile.storesAlwaysHiddenSection)
    }

    @Test("A profile that stores the switch says so, and the flag is never written to the file")
    func storedSwitch() throws {
        let profile = try Self.decode(#"{"name": "New", "advancedSettings": {"enableAlwaysHiddenSection": false}, "hotkeyActions": ["a"]}"#)
        #expect(profile.storesAlwaysHiddenSection)
        #expect(profile.hotkeyActions == ["a"])
        let json = try String(decoding: JSONEncoder().encode(profile), as: UTF8.self)
        #expect(!json.contains("storesAlwaysHiddenSection"))
        #expect(json.contains("hotkeyActions"))
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

    @Test("Importing a file restores its apply shortcut")
    func importRestoresShortcut() throws {
        try ProfileTestDirectory.withManager(seeding: []) { manager, tmp in
            let shortcut = Data("⌃⌥2".utf8)
            let bundle = try ProfileExportBundle(entries: [ProfileExportEntry(profile: Self.profile(named: "Imported"), applyShortcut: shortcut)])
            let file = tmp.appendingPathComponent("bundle.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(bundle).write(to: file)

            try manager.importProfile(from: file)

            let imported = try #require(manager.profiles.first { $0.name == "Imported" })
            #expect(ProfileApplyShortcuts().shortcut(for: imported.id) == shortcut)
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
}
