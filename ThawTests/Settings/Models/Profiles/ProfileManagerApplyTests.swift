//
//  ProfileManagerApplyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// Applying profiles to an AppState that was never set up, so no layout engine
/// runs and no item moves. Profiles live in a throwaway directory and settings
/// in a throwaway suite.
@MainActor
@Suite("Profile manager apply", .serialized, .scratchDefaults)
struct ProfileManagerApplyTests {
    private static let combination = KeyCombination(key: KeyCode(rawValue: 0x6A), modifiers: [.command, .option, .control, .shift])

    /// An AppState whose spacing offset already matches the values on disk,
    /// so the apply's spacing step finds nothing to write.
    private static func makeAppState() throws -> AppState {
        let appState = AppState()
        let offset = (DisplaySettingsManager.currentSystemSpacing() ?? 16) - 16
        try #require(
            appState.spacingManager.isOnDisk(offset: offset),
            "spacing and padding on disk differ, so an apply would rewrite them"
        )
        appState.spacingManager.offset = offset
        appState.spacingManager.spacingApplyMode = .writeOnly
        return appState
    }

    private static func storedProfileHotkeys() -> [String: Data] {
        Defaults.dictionary(forKey: .profileHotkeys) as? [String: Data] ?? [:]
    }

    @Test("Applying a profile restores its settings, hotkeys, displays and names, then reports that no layout engine ran")
    func applyRestoresSnapshot() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let appState = try Self.makeAppState()
        let actions = HotkeyAction.settingsActions
        try #require(actions.count >= 2)

        appState.settings.general.showOnHover = !Defaults.DefaultValue.showOnHover
        let id = try manager.saveProfile(name: "Work", from: appState)
        appState.settings.general.showOnHover = Defaults.DefaultValue.showOnHover
        appState.settings.hotkeys.hotkey(withAction: actions[1])?.keyCombination = Self.combination

        var profile = try manager.loadProfile(id: id)
        profile.hotkeys = try [
            actions[0].rawValue: JSONEncoder().encode(Self.combination),
            actions[1].rawValue: Data("not a key combination".utf8),
        ]
        let global = DisplayThawBarConfiguration.defaultConfiguration.withGridColumns(7)
        profile.globalDisplayConfiguration = global
        profile.displayConfigurations = ["DISPLAY": .defaultConfiguration.withUseThawBar(true)]
        profile.menuBarLayout.customNames = ["com.example:item": "Example"]
        profile.menuBarLayout.itemHotkeys = ["com.example:item": Data([1, 2])]
        profile.menuBarLayout.pinnedHiddenBundleIDs = ["com.example.hidden"]
        profile.menuBarLayout.itemOrder = ["hidden": ["com.example.hidden:item"]]
        let placement = try #require(profile.menuBarLayout.newItemsPlacement)

        manager.applyProfile(profile, to: appState, relaunchesApps: false)
        let task = try #require(manager.layoutTask)
        #expect(manager.layoutTaskProfileID == id)
        await task.value
        defer {
            for action in actions.prefix(2) {
                appState.settings.hotkeys.hotkey(withAction: action)?.keyCombination = nil
            }
        }

        #expect(appState.settings.general.showOnHover == !Defaults.DefaultValue.showOnHover)
        #expect(appState.settings.hotkeys.hotkey(withAction: actions[0])?.keyCombination == Self.combination)
        #expect(
            appState.settings.hotkeys.hotkey(withAction: actions[1])?.keyCombination == Self.combination,
            "a binding that cannot be decoded leaves the current one"
        )
        #expect(appState.settings.displaySettings.globalConfiguration == global)
        #expect(appState.settings.displaySettings.configurations == profile.displayConfigurations)
        #expect(Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] == ["com.example:item": "Example"])
        #expect(Defaults.dictionary(forKey: .menuBarItemHotkeys) as? [String: Data] == ["com.example:item": Data([1, 2])])
        #expect(appState.itemManager.newItemsPlacement == placement)
        #expect(appState.itemManager.pinnedHiddenBundleIDs == ["com.example.hidden"])
        #expect(appState.itemManager.activeProfileLayout?.itemOrder == ["hidden": ["com.example.hidden:item"]])
        #expect(manager.layoutDidNotRun, "an AppState that was never set up has no layout engine")
        #expect(manager.layoutTask == nil)
    }

    @Test("Reapplying runs the active profile again and keeps it active")
    func reapplyActiveProfile() async throws {
        try await withManager(seeding: ["A"]) { manager, _ in
            let id = manager.profiles[0].id
            let appState = try Self.makeAppState()
            manager.appState = appState
            manager.activeProfileID = id

            manager.reapplyActiveProfile()

            let task = try #require(manager.layoutTask)
            #expect(manager.layoutTaskProfileID == id)
            await task.value
            #expect(manager.activeProfileID == id)
        }
    }

    @Test("Reapplying an active profile whose file is gone starts nothing")
    func reapplyMissingProfile() async throws {
        try await withManager(seeding: ["A"]) { manager, tmp in
            let id = manager.profiles[0].id
            try FileManager.default.removeItem(at: tmp.appendingPathComponent("\(id.uuidString).json"))
            let appState = try Self.makeAppState()
            manager.appState = appState
            manager.activeProfileID = id

            manager.reapplyActiveProfile()

            #expect(manager.layoutTask == nil)
            #expect(manager.activeProfileID == id)
        }
    }

    @Test("A Focus Filter request for another profile applies it and marks the filter active")
    func focusFilterAppliesProfile() async throws {
        try await withManager(seeding: ["A", "B"]) { manager, _ in
            let first = manager.profiles[0].id
            let second = manager.profiles[1].id
            let appState = try Self.makeAppState()
            manager.appState = appState
            manager.activeProfileID = first

            await manager.applyFocusFilterProfile(requested: second.uuidString)

            #expect(manager.activeProfileID == second)
            #expect(manager.focusFilterActive)
            #expect(manager.layoutTaskProfileID == second)
            await manager.layoutTask?.value
        }
    }

    @Test("A Focus Filter request for a profile whose file is gone changes nothing")
    func focusFilterMissingProfile() async throws {
        try await withManager(seeding: ["A"]) { manager, tmp in
            let id = manager.profiles[0].id
            try FileManager.default.removeItem(at: tmp.appendingPathComponent("\(id.uuidString).json"))
            let appState = try Self.makeAppState()
            manager.appState = appState

            await manager.applyFocusFilterProfile(requested: id.uuidString)

            #expect(manager.activeProfileID == nil)
            #expect(!manager.focusFilterActive)
            #expect(manager.layoutTask == nil)
        }
    }

    @Test("When Focus ends, the profile of the display with the menu bar applies")
    func focusEndRevertsToDisplayProfile() async throws {
        try await withManager(seeding: ["Focus", "Desk"]) { manager, _ in
            let deskID = manager.profiles[1].id
            let activeDisplay = Bridging.getActiveMenuBarDisplayUUID()
            if let activeDisplay {
                manager.setAssociatedDisplay(uuid: activeDisplay, displayName: "Display", forProfileID: deskID)
            }

            try await Self.endFocus(on: manager)

            #expect(manager.activeProfileID == (activeDisplay == nil ? manager.profiles[0].id : deskID))
        }
    }

    @Test("When Focus ends, a profile that owns the current Space wins over the display's")
    func focusEndRevertsToSpaceProfile() async throws {
        try await withManager(seeding: ["Focus", "Desk", "Space"]) { manager, _ in
            let deskID = manager.profiles[1].id
            let spaceID = manager.profiles[2].id
            let activeDisplay = Bridging.getActiveMenuBarDisplayUUID()
            let activeSpace = SpaceInfo.activeSpace().persistentKey
            if let activeDisplay {
                manager.setAssociatedDisplay(uuid: activeDisplay, displayName: "Display", forProfileID: deskID)
            }
            if let activeSpace {
                manager.setAssociatedSpace(key: activeSpace, spaceName: "Desktop", forProfileID: spaceID)
            }

            try await Self.endFocus(on: manager)

            let expected = activeSpace != nil ? spaceID : activeDisplay != nil ? deskID : manager.profiles[0].id
            #expect(manager.activeProfileID == expected)
        }
    }

    /// Activates Focus for the first profile, then ends it, and waits for the profile the end switched to.
    private static func endFocus(on manager: ProfileManager) async throws {
        let focusID = manager.profiles[0].id
        let appState = try makeAppState()
        manager.appState = appState
        manager.activeProfileID = focusID
        var systemProfileID: String? = focusID.uuidString
        manager.focusFilterSignal = FocusFilterSignal { systemProfileID }
        await manager.handleFocusFilterSignal()
        #expect(manager.focusFilterActive)

        systemProfileID = nil
        await manager.handleFocusFilterSignal()

        #expect(!manager.focusFilterActive)
        if manager.activeProfileID != focusID {
            #expect(manager.layoutTaskProfileID == manager.activeProfileID)
        }
        await manager.layoutTask?.value
        #expect(manager.appState === appState)
    }

    @Test("Rebuilding profile hotkeys loads saved bindings, drops ones for deleted profiles and saves later changes")
    func rebuildProfileHotkeys() throws {
        try ProfileTestDirectory.withManager(seeding: ["A", "B"]) { manager, _ in
            let first = manager.profiles[0].id
            let second = manager.profiles[1].id
            let orphan = UUID().uuidString
            let data = try JSONEncoder().encode(Self.combination)
            Defaults.set([first.uuidString: data, orphan: data], forKey: .profileHotkeys)
            let appState = AppState()
            manager.appState = appState

            manager.rebuildProfileHotkeys()

            let firstHotkey = try #require(manager.profileHotkeys[first])
            let secondHotkey = try #require(manager.profileHotkeys[second])
            defer {
                firstHotkey.keyCombination = nil
                secondHotkey.keyCombination = nil
            }
            #expect(Set(Self.storedProfileHotkeys().keys) == [first.uuidString], "the deleted profile's binding is dropped")
            #expect(firstHotkey.keyCombination == Self.combination)
            #expect(firstHotkey.action == .profileApply)
            #expect(secondHotkey.keyCombination == nil)
            #expect(manager.hotkeyProfileMap[ObjectIdentifier(firstHotkey)] == first)
            #expect(manager.hotkeyProfileMap[ObjectIdentifier(secondHotkey)] == second)

            secondHotkey.keyCombination = Self.combination
            #expect(Set(Self.storedProfileHotkeys().keys) == [first.uuidString, second.uuidString])
            #expect(manager.hotkeyProfileMap[ObjectIdentifier(secondHotkey)] == second)

            firstHotkey.keyCombination = nil
            #expect(Set(Self.storedProfileHotkeys().keys) == [second.uuidString])
            #expect(manager.hotkeyProfileMap[ObjectIdentifier(firstHotkey)] == nil)
        }
    }

    @Test("Rebuilding replaces the old hotkeys and turns them off")
    func rebuildDisablesOldHotkeys() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, _ in
            let id = manager.profiles[0].id
            try Defaults.set([id.uuidString: JSONEncoder().encode(Self.combination)], forKey: .profileHotkeys)
            let appState = AppState()
            manager.appState = appState
            manager.rebuildProfileHotkeys()
            let old = try #require(manager.profileHotkeys[id])
            #expect(old.isEnabled)

            manager.rebuildProfileHotkeys()
            let new = try #require(manager.profileHotkeys[id])
            defer { new.keyCombination = nil }

            #expect(old !== new)
            #expect(!old.isEnabled)
            #expect(new.isEnabled)
            #expect(manager.hotkeyProfileMap.count == 1)
        }
    }

    @Test("A layout update to the active profile rearms the item manager's cached layout")
    func layoutUpdateRearmsActiveProfile() throws {
        try ProfileTestDirectory.withManager(seeding: ["A", "B"]) { manager, _ in
            let active = manager.profiles[0].id
            let other = manager.profiles[1].id
            let itemManager = AppState().itemManager
            manager.activeProfileID = active

            try manager.updateProfileLayout(id: other, itemManager: itemManager)
            #expect(itemManager.activeProfileLayout == nil, "an inactive profile leaves the cached layout alone")

            try manager.updateProfileLayout(id: active, itemManager: itemManager)
            let layout = try manager.loadProfile(id: active).menuBarLayout
            let armed = try #require(itemManager.activeProfileLayout)
            #expect(armed.itemOrder == (layout.itemOrder ?? [:]))
            #expect(armed.sectionOrder == layout.savedSectionOrder)
            #expect(armed.pinnedHidden == Set(layout.pinnedHiddenBundleIDs))
        }
    }

    @Test("A manifest write that fails is reported once")
    func manifestWriteFailureIsReported() throws {
        try ProfileTestDirectory.withManager(seeding: ["A"]) { manager, tmp in
            let id = manager.profiles[0].id
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tmp.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path) }

            manager.setLayoutBehavior(reappliesAtLaunch: true, forProfileID: id)

            #expect(manager.takeManifestError() != nil)
            #expect(manager.takeManifestError() == nil)
            #expect(manager.profiles[0].reappliesAtLaunch, "the change stays in memory")
        }
    }

    private func withManager(
        seeding names: [String],
        _ body: (ProfileManager, URL) async throws -> Void
    ) async throws {
        let tmp = try ProfileTestDirectory.make(seeding: names)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await body(ProfileManager(profilesDirectory: tmp), tmp)
    }
}
