//
//  ProfileSwitchesSectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// The "What switches to this profile" section drawn off screen and read as VoiceOver reads it.
/// Its pickers open menus and its Focus button opens System Settings, so neither is pressed;
/// what they save is checked through the bindings they write to.
@MainActor
@Suite("The profile switches section", .serialized, .scratchDefaults)
struct ProfileSwitchesSectionTests {
    private static let size = CGSize(width: 760, height: 600)

    private func render(_ manager: ProfileManager, _ profile: ProfileMetadata, appState: AppState) async -> OffscreenRender<AnyView> {
        let view = ThawForm {
            ProfileSwitchesSection(
                profileManager: manager,
                displaySettings: appState.settings.displaySettings,
                profile: profile,
                errorMessage: .constant(nil)
            )
        }
        .environment(appState)
        .frame(width: Self.size.width, height: Self.size.height)
        let render = OffscreenRender(AnyView(view), size: Self.size)
        let title = "What switches to this profile"
        await render.settle { render.texts().contains(title) }
        #expect(render.texts().contains(title), "the section has appeared")
        return render
    }

    /// What the section's two pickers show as chosen: the display, then the Space.
    private func pickerValues(in render: OffscreenRender<AnyView>) -> [String] {
        render.elements()
            .filter { OffscreenAccessibility.role(of: $0) == .popUpButton }
            .compactMap { OffscreenAccessibility.string("accessibilityValue", of: $0) }
    }

    @Test("The shortcut recorder shows only once the profile has a hotkey to record into")
    func shortcutRecorder() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["Work"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let profile = try #require(manager.profiles.first)
        let appState = AppState()

        let before = await render(manager, profile, appState: appState)
        #expect(manager.profileHotkeys.isEmpty, "a manager without an AppState builds no hotkeys")
        #expect(!before.texts().contains("Keyboard shortcut"))

        manager.appState = appState
        manager.rebuildProfileHotkeys()
        let hotkey = try #require(manager.profileHotkeys[profile.id])
        #expect(hotkey.keyCombination == nil, "nothing is registered with the system")

        let after = await render(manager, profile, appState: appState)
        await after.settle { after.texts().contains("Keyboard shortcut") }
        #expect(after.texts().contains("Keyboard shortcut"))
        #expect(!after.elements(role: .button, label: "Record Shortcut").isEmpty)
    }

    @Test("The pickers show the profile's own display and Space, marked when they are gone")
    func pickersShowTheProfilesChoices() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["Work", "Home"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let work = manager.profiles[0].id
        manager.setAssociatedDisplay(uuid: "DISPLAY", displayName: "Studio", forProfileID: work)
        manager.setAssociatedSpace(key: "SPACE", spaceName: "Desktop 9", forProfileID: work)
        let appState = AppState()

        let chosen = await render(manager, manager.profiles[0], appState: appState)
        await chosen.settle { pickerValues(in: chosen).count == 2 }
        #expect(pickerValues(in: chosen) == ["Studio · Disconnected", "Desktop 9 · Missing"])

        let unchosen = await render(manager, manager.profiles[1], appState: appState)
        await unchosen.settle { pickerValues(in: unchosen).count == 2 }
        #expect(pickerValues(in: unchosen) == ["None", "None"], "another profile's display and Space are not this one's")
    }

    /// The section as a plain value, with what it reports to the page kept in a box the test can read.
    private func section(
        _ manager: ProfileManager,
        profile: ProfileMetadata,
        displaySettings: DisplaySettingsManager,
        error: ErrorBox
    ) -> ProfileSwitchesSection {
        ProfileSwitchesSection(
            profileManager: manager,
            displaySettings: displaySettings,
            profile: profile,
            errorMessage: Binding { error.message } set: { error.message = $0 }
        )
    }

    private final class ErrorBox {
        var message: String?
    }

    @Test("Choosing a display saves it for the profile and takes it from another, and None clears it")
    func displayChoiceSaves() throws {
        try ProfileTestDirectory.withManager(seeding: ["Work", "Home"]) { manager, tmp in
            let displaySettings = DisplaySettingsManager()
            let error = ErrorBox()
            let work = section(manager, profile: manager.profiles[0], displaySettings: displaySettings, error: error)
            let home = section(manager, profile: manager.profiles[1], displaySettings: displaySettings, error: error)

            work.displayBinding.wrappedValue = "DISPLAY"
            #expect(work.displayBinding.wrappedValue == "DISPLAY")
            #expect(ProfileManager(profilesDirectory: tmp).profiles[0].associatedDisplayUUID == "DISPLAY", "it is saved")

            home.displayBinding.wrappedValue = "DISPLAY"
            #expect(home.displayBinding.wrappedValue == "DISPLAY")
            #expect(work.displayBinding.wrappedValue.isEmpty, "a display belongs to one profile at a time")

            home.displayBinding.wrappedValue = ""
            #expect(home.displayBinding.wrappedValue.isEmpty)
            #expect(error.message == nil)
        }
    }

    @Test("Choosing a Space saves its key and name, keeps the name of a Space that is gone, and None clears it")
    func spaceChoiceSaves() throws {
        try ProfileTestDirectory.withManager(seeding: ["Work", "Home"]) { manager, tmp in
            let displaySettings = DisplaySettingsManager()
            let error = ErrorBox()
            let work = section(manager, profile: manager.profiles[0], displaySettings: displaySettings, error: error)
            let home = section(manager, profile: manager.profiles[1], displaySettings: displaySettings, error: error)
            let desktop = SpaceChoice(id: "SPACE-1", label: "Desktop 1", kind: .desktop, ownerPID: nil, isMissing: false)
            let groups = [SpaceDisplayGroup(id: "DISPLAY", displayName: "Studio", hasMenuBar: true, spaces: [desktop])]

            work.spaceBinding(groups: groups).wrappedValue = "SPACE-1"
            #expect(work.spaceBinding(groups: groups).wrappedValue == "SPACE-1")
            let saved = ProfileManager(profilesDirectory: tmp).profiles[0]
            #expect(saved.associatedSpaceKey == "SPACE-1")
            #expect(saved.associatedSpaceName == "Desktop 1", "the label of the chosen Space is kept with it")

            home.spaceBinding(groups: []).wrappedValue = "SPACE-1"
            #expect(manager.profiles[1].associatedSpaceName == "Desktop 1", "a Space the window server no longer lists keeps its stored name")
            #expect(work.spaceBinding(groups: groups).wrappedValue.isEmpty, "a Space belongs to one profile at a time")

            home.spaceBinding(groups: groups).wrappedValue = ""
            #expect(home.spaceBinding(groups: groups).wrappedValue.isEmpty)
            #expect(error.message == nil)
        }
    }

    @Test("A choice that cannot be saved is reported to the page")
    func failedSaveIsReported() throws {
        try ProfileTestDirectory.withManager(seeding: ["Work"]) { manager, tmp in
            let displaySettings = DisplaySettingsManager()
            let error = ErrorBox()
            let work = section(manager, profile: manager.profiles[0], displaySettings: displaySettings, error: error)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: tmp.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path) }

            work.displayBinding.wrappedValue = "DISPLAY"
            let display = try #require(error.message, "a display that cannot be saved is reported")

            error.message = nil
            work.spaceBinding(groups: []).wrappedValue = "SPACE-1"
            #expect(error.message != nil, "a Space that cannot be saved is reported")
            #expect(!display.isEmpty)
        }
    }
}

@MainActor
@Suite("Profile display picker")
struct ProfileDisplayChoicesTests {
    private typealias DisplayInfo = DisplaySettingsManager.DisplayInfo

    private static func profile(displayUUID: String?, displayName: String? = nil) -> ProfileMetadata {
        var profile = ProfileMetadata(id: UUID(), name: "Profile", createdAt: .distantPast, modifiedAt: .distantPast)
        profile.associatedDisplayUUID = displayUUID
        profile.associatedDisplayName = displayName
        return profile
    }

    private static let builtIn = DisplayInfo(id: "built-in", displayID: 1, name: "Built-in Display", hasNotch: true, isConnected: true)

    @Test("Connected displays come first, then a disconnected one a profile still names")
    func keepsDisconnectedChoices() {
        let choices = ProfileSwitchesSection.displayChoices(
            connected: [Self.builtIn],
            profiles: [
                Self.profile(displayUUID: "built-in", displayName: "Old Name"),
                Self.profile(displayUUID: "studio", displayName: "Studio Display"),
                Self.profile(displayUUID: "studio", displayName: "Studio Display"),
                Self.profile(displayUUID: "unnamed"),
                Self.profile(displayUUID: nil),
            ]
        )
        #expect(choices.map(\.id) == ["built-in", "studio", "unnamed"])
        #expect(choices[0].name == "Built-in Display")
        #expect(choices[1].name == "Studio Display")
        #expect(choices[1].isConnected == false)
        #expect(choices[1].displayID == nil)
        #expect(choices[2].name == "unnamed")
    }

    @Test("The label names the notch and a disconnected display")
    func labels() {
        let studio = DisplayInfo(id: "studio", displayID: nil, name: "Studio Display", hasNotch: false, isConnected: false)
        #expect(ProfileSwitchesSection.label(for: Self.builtIn) == "Built-in Display · Notch")
        #expect(ProfileSwitchesSection.label(for: studio) == "Studio Display · Disconnected")
    }
}

@MainActor
@Suite("The profile Layout section", .serialized)
struct ProfileLayoutBehaviorSectionTests {
    @Test("Shows both switches")
    func showsBothSwitches() async throws {
        let tmp = try ProfileTestDirectory.make(seeding: ["Default"])
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let profile = try #require(manager.profiles.first)
        let view = ProfileLayoutBehaviorSection(profileManager: manager, profile: profile, errorMessage: .constant(nil))
            .frame(width: 520, height: 220)
        let render = OffscreenRender(view, size: CGSize(width: 520, height: 220))
        let texts = await render.texts(once: "Keep layout changes in this profile")
        #expect(texts.contains { $0.contains("Keep layout changes in this profile") })
        #expect(texts.contains { $0.contains("Apply again when") })
    }

    @Test("Each switch reads and saves its own setting")
    func switchesSave() throws {
        try ProfileTestDirectory.withManager(seeding: ["Default"]) { manager, tmp in
            let profile = try #require(manager.profiles.first)
            var error: String?
            let section = ProfileLayoutBehaviorSection(
                profileManager: manager,
                profile: profile,
                errorMessage: Binding { error } set: { error = $0 }
            )
            #expect(section.keepsChanges.wrappedValue)
            #expect(!section.reappliesAtLaunch.wrappedValue)

            section.keepsChanges.wrappedValue = false
            section.reappliesAtLaunch.wrappedValue = true

            let reloaded = ProfileManager(profilesDirectory: tmp)
            #expect(reloaded.profiles.first?.keepsLayoutChanges == false)
            #expect(reloaded.profiles.first?.reappliesAtLaunch == true)
            #expect(error == nil)
        }
    }
}
