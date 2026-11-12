//
//  ProfileSettingsPaneActionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// The Profiles page drawn off screen and worked through its own controls, against an AppState
/// that is never started and profiles in a throwaway folder. Nothing here opens an alert, a
/// panel or a menu: Delete, Import and Export are left alone because they do.
@MainActor
@Suite("Profiles page actions", .serialized, .scratchDefaults)
struct ProfileSettingsPaneActionTests {
    private static let size = CGSize(width: 760, height: 2400)

    /// An AppState whose spacing already matches the values on disk and is only ever written,
    /// so nothing a test does can restart an app.
    private static func makeAppState() throws -> AppState {
        let appState = AppState()
        let offset = (DisplaySettingsManager.currentSystemSpacing() ?? 16) - 16
        try #require(
            appState.spacingManager.isOnDisk(offset: offset),
            "spacing and padding on disk differ, so an apply would rewrite them"
        )
        appState.spacingManager.offset = offset
        appState.spacingManager.spacingApplyMode = .writeOnly
        appState.settings.displaySettings.spacingApplyMode = .writeOnly
        return appState
    }

    /// Saves a spacing offset for every display into the first profile.
    private static func setSpacingOffset(_ offset: Double, ofFirstProfileIn manager: ProfileManager) throws {
        var profile = try manager.loadProfile(id: manager.profiles[0].id)
        profile.globalDisplayConfiguration = profile.globalDisplayConfiguration.withItemSpacingOffset(offset)
        profile.displayConfigurations = [:]
        try manager.replaceProfile(profile)
    }

    private typealias Page = OffscreenRender<AnyView>

    /// Draws the page over a folder seeded with the named profiles and waits for it to show.
    private func withPage(
        seeding names: [String],
        fileChoosers: ProfileSettingsPane.FileChoosers = .init(),
        prepare: (ProfileManager, AppState) throws -> Void = { _, _ in /* Most tests start from the seeded profiles as they are. */ },
        _ body: (ProfileManager, AppState, Page) async throws -> Void
    ) async throws {
        let tmp = try ProfileTestDirectory.make(seeding: names)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let appState = try Self.makeAppState()
        try prepare(manager, appState)
        let page = OffscreenRender(
            AnyView(
                ProfileSettingsPane(profileManager: manager, fileChoosers: fileChoosers)
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
        await page.settle { (try? page.pixels())?.contains { $0 != 0 } == true }
        try await body(manager, appState, page)
    }

    /// The row of the profile with this name.
    private func row(_ name: String, in page: Page) throws -> NSObject {
        try #require(page.elements().first {
            OffscreenAccessibility.role(of: $0) == .button
                && OffscreenAccessibility.label(of: $0)?.hasPrefix(name + ",") == true
        })
    }

    /// The page's text fields: the rename field of a row being renamed, then the new profile name.
    private func fields(in page: Page) -> [NSTextField] {
        page.views(NSTextField.self).filter(\.isEditable)
    }

    /// What the page's pickers show as chosen.
    private func popUpValues(in page: Page) -> [String] {
        page.elements()
            .filter { OffscreenAccessibility.role(of: $0) == .popUpButton }
            .compactMap { OffscreenAccessibility.string("accessibilityValue", of: $0) }
    }

    private func undoManager(of page: Page) throws -> UndoManager {
        try #require(page.host.undoManager)
    }

    @Test("Save Current keeps the setup as a new active profile, and undo and redo take it away and bring it back")
    func savesCurrentSetup() async throws {
        try await withPage(seeding: []) { manager, appState, page in
            let undo = try undoManager(of: page)
            #expect(page.texts().contains { $0.hasPrefix("No profiles yet") })

            var field = try #require(fields(in: page).first)
            page.type("   ", into: field)
            page.submit(field)
            #expect(manager.profiles.isEmpty, "a name of spaces saves nothing")

            appState.settings.visibility.showOnHover = !Defaults.DefaultValue.showOnHover
            page.type("Desk", into: field)
            await page.settle { (try? page.press("Save Current")) != nil && !manager.profiles.isEmpty }
            let id = try #require(manager.profiles.first?.id)
            #expect(manager.profiles.map(\.name) == ["Desk"])
            #expect(manager.activeProfileID == id)
            #expect(try manager.loadProfile(id: id).generalSettings.showOnHover == !Defaults.DefaultValue.showOnHover)
            await page.settle { fields(in: page).first?.stringValue.isEmpty == true }
            #expect(fields(in: page).first?.stringValue.isEmpty == true, "the name field empties for the next profile")
            #expect(undo.undoActionName == "Create Profile")

            undo.undo()
            #expect(manager.profiles.isEmpty)
            #expect(manager.activeProfileID == nil)
            #expect(undo.redoActionName == "Create Profile")

            undo.redo()
            #expect(manager.profiles.map(\.id) == [id])
            #expect(manager.activeProfileID == id, "redo makes it the active profile again")

            await page.settle { fields(in: page).count == 1 }
            field = try #require(fields(in: page).first)
            page.type("Travel", into: field)
            page.submit(field)
            #expect(manager.profiles.map(\.name) == ["Desk", "Travel"], "Return saves like the button")
        }
    }

    @Test("Rename from a row's menu saves the new name, keeps the old one for a blank name, and undoes")
    func renames() async throws {
        try await withPage(seeding: ["Work", "Home"]) { manager, _, page in
            let undo = try undoManager(of: page)
            let id = manager.profiles[0].id

            try page.contextMenu(over: row("Work", in: page)).choose("Rename")
            await page.settle { fields(in: page).count == 2 }
            var field = try #require(fields(in: page).first)
            #expect(field.stringValue == "Work", "the field starts with the current name")
            page.type("Office", into: field)
            try page.press("Done")
            #expect(manager.profiles.map(\.name) == ["Office", "Home"])
            #expect(try manager.loadProfile(id: id).name == "Office")
            #expect(undo.undoActionName == "Rename Profile")
            await page.settle { fields(in: page).count == 1 }
            #expect(fields(in: page).count == 1, "the row leaves editing")

            undo.undo()
            #expect(manager.profiles.map(\.name) == ["Work", "Home"])
            undo.redo()
            #expect(manager.profiles.map(\.name) == ["Office", "Home"])

            await page.settle { (try? row("Office", in: page)) != nil }
            try page.contextMenu(over: row("Office", in: page)).choose("Rename")
            await page.settle { fields(in: page).count == 2 }
            field = try #require(fields(in: page).first)
            page.type("   ", into: field)
            page.submit(field)
            await page.settle { fields(in: page).count == 1 }
            #expect(fields(in: page).count == 1, "Return ends editing")
            #expect(manager.profiles.map(\.name) == ["Office", "Home"], "a blank name changes nothing")
        }
    }

    @Test("Duplicate from a row's menu adds a copy at the end, and undo removes it")
    func duplicates() async throws {
        try await withPage(seeding: ["Work", "Home"]) { manager, _, page in
            let undo = try undoManager(of: page)

            try page.contextMenu(over: row("Home", in: page)).choose("Duplicate")
            #expect(manager.profiles.map(\.name) == ["Work", "Home", "Home Copy"])
            let copy = try #require(manager.profiles.last?.id)
            #expect(undo.undoActionName == "Duplicate Profile")

            undo.undo()
            #expect(manager.profiles.map(\.name) == ["Work", "Home"])
            #expect(throws: (any Error).self) { try manager.loadProfile(id: copy) }

            undo.redo()
            #expect(manager.profiles.map(\.id).last == copy, "redo brings back the same copy")
        }
    }

    /// Answers the page's file choosers from the test, so no panel opens, and records what was suggested.
    @MainActor
    private final class Choices {
        var answer: URL?
        var suggestedNames = [String]()

        var choosers: ProfileSettingsPane.FileChoosers {
            var choosers = ProfileSettingsPane.FileChoosers()
            choosers.save = { [self] name in
                suggestedNames.append(name)
                return answer
            }
            choosers.open = { [self] in answer }
            return choosers
        }
    }

    @Test("Export writes the profile where the chooser says, with a slash made safe, and a cancelled chooser writes nothing")
    func exportsOneProfile() async throws {
        let folder = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appendingPathComponent("out.json")
        let choices = Choices()
        try await withPage(seeding: ["Work/Home", "Desk"], fileChoosers: choices.choosers) { _, _, page in
            try page.contextMenu(over: row("Work/Home", in: page)).choose("Export…")
            #expect(choices.suggestedNames == ["Work-Home.json"], "a slash in the name becomes a dash")
            #expect(!FileManager.default.fileExists(atPath: target.path), "a cancelled chooser writes nothing")

            choices.answer = target
            try page.contextMenu(over: row("Work/Home", in: page)).choose("Export…")
            let file = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as? [String: Any])
            let entries = try #require(file["entries"] as? [[String: Any]])
            let names = entries.compactMap { ($0["profile"] as? [String: Any])?["name"] as? String }
            #expect(names == ["Work/Home"], "the file holds the chosen profile and only that one")
        }
    }

    @Test("Export Profiles writes every profile, and Import brings a profile back in")
    func exportsAllAndImports() async throws {
        let folder = try ProfileTestDirectory.make(seeding: [])
        defer { try? FileManager.default.removeItem(at: folder) }
        let everything = folder.appendingPathComponent("all.json")
        let single = folder.appendingPathComponent("single.json")
        let choices = Choices()
        try await withPage(seeding: ["Work", "Desk"], fileChoosers: choices.choosers) { manager, _, page in
            try page.press("Export Profiles…")
            #expect(choices.suggestedNames == ["\(Constants.displayName) Profiles.json"])
            #expect(!FileManager.default.fileExists(atPath: everything.path), "a cancelled chooser writes nothing")

            choices.answer = everything
            try page.press("Export Profiles…")
            let written = try String(contentsOf: everything, encoding: .utf8)
            #expect(written.contains("Work") && written.contains("Desk"), "every profile is in the file")

            try page.contextMenu(over: row("Desk", in: page)).choose("Export…")
            choices.answer = single
            try page.contextMenu(over: row("Desk", in: page)).choose("Export…")
            #expect(FileManager.default.fileExists(atPath: single.path))

            choices.answer = nil
            try page.press("Import Profiles…")
            #expect(manager.profiles.count == 2, "a cancelled chooser imports nothing")

            choices.answer = single
            try page.press("Import Profiles…")
            #expect(manager.profiles.count == 3, "the chosen file adds its profile")
        }
    }

    @Test("Update with Current Setup saves into the selected profile only, whole or in part, and undoes")
    func updatesSelectedProfile() async throws {
        try await withPage(seeding: ["Work", "Home"], prepare: { manager, _ in
            manager.setAssociatedDisplay(uuid: "DISPLAY", displayName: "Studio", forProfileID: manager.profiles[1].id)
        }) { manager, appState, page in
            let undo = try undoManager(of: page)
            let work = manager.profiles[0].id
            let home = manager.profiles[1].id
            let original = Defaults.DefaultValue.showOnHover
            @MainActor func saved(_ id: UUID) throws -> Bool {
                try manager.loadProfile(id: id).generalSettings.showOnHover
            }
            try #require(try saved(work) == original && saved(home) == original)

            // Home's display shows in the picker once the page has moved to Home's details.
            #expect(!popUpValues(in: page).contains("Studio · Disconnected"), "the page opens on the first profile")
            try OffscreenAccessibility.press(row("Home", in: page))
            await page.settle { popUpValues(in: page).contains("Studio · Disconnected") }
            #expect(popUpValues(in: page).contains("Studio · Disconnected"), "picking a row shows that profile's details")
            appState.settings.visibility.showOnHover = !original

            try page.press("Update with Current Setup")
            #expect(try saved(home) == !original)
            #expect(try saved(work) == original, "the profile that is not selected stays as it was")
            #expect(undo.undoActionName == "Save Profile")
            undo.undo()
            #expect(try saved(home) == original)

            let control = try #require(page.views(NSSegmentedControl.self).first)
            let stamp = try #require(manager.profiles.last?.modifiedAt)
            try page.menu(of: control, segment: 1).choose("Update Layout Only")
            #expect(undo.undoActionName == "Save Layout")
            #expect(try saved(home) == original, "a layout update leaves the settings")
            #expect(try #require(manager.profiles.last?.modifiedAt) > stamp)

            try page.menu(of: control, segment: 1).choose("Update Settings Only")
            #expect(undo.undoActionName == "Save Configuration")
            #expect(try saved(home) == !original)
            #expect(try saved(work) == original)
            undo.undo()
            #expect(try saved(home) == original)

            try page.menu(of: control, segment: 1).choose("Update Settings in Every Profile")
            #expect(undo.undoActionName == "Save Configuration on All Profiles")
            #expect(try saved(home) == !original)
            #expect(try saved(work) == !original)
            undo.undo()
            #expect(try saved(home) == original)
            #expect(try saved(work) == original, "one undo puts every profile back")
        }
    }

    @Test("The arrow keys step through the rows once the list has keyboard focus")
    func arrowKeysStepThroughRows() async throws {
        try await withPage(seeding: ["Work", "Home"], prepare: { manager, _ in
            manager.setAssociatedDisplay(uuid: "DISPLAY", displayName: "Studio", forProfileID: manager.profiles[1].id)
        }) { _, _, page in
            let window = try #require(page.host.window)
            // Sends an arrow key to whatever has keyboard focus in the page's window, which is never shown.
            @MainActor func press(arrow keyCode: UInt16, character: Int) throws {
                let characters = try String(#require(UnicodeScalar(character)))
                let event = try #require(NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: keyCode
                ))
                window.firstResponder?.keyDown(with: event)
            }
            let showsHome = { popUpValues(in: page).contains("Studio · Disconnected") }
            try #require(!showsHome(), "the page opens on the first profile")

            // The list is one keyboard stop; how many stops come before it depends on the
            // Mac's keyboard navigation setting, so move on until the Down Arrow reaches it.
            window.makeFirstResponder(page.host)
            for _ in 0 ..< 8 where !showsHome() {
                window.selectNextKeyView(nil)
                // SwiftUI moves its own focus to the stop on a later update, and says nothing when it has.
                await page.settle(within: .milliseconds(200)) { false }
                try press(arrow: 125, character: NSDownArrowFunctionKey)
                await page.settle(within: .milliseconds(300)) { showsHome() }
            }
            #expect(showsHome(), "Down Arrow moves to the next profile")

            try press(arrow: 125, character: NSDownArrowFunctionKey)
            await page.settle(within: .milliseconds(300)) { !showsHome() }
            #expect(showsHome(), "Down Arrow on the last row stays there")

            try press(arrow: 126, character: NSUpArrowFunctionKey)
            await page.settle { !showsHome() }
            #expect(!showsHome(), "Up Arrow moves back to the first profile")
        }
    }

    @Test("Apply makes the profile active and restores its settings without asking, when spacing is only saved")
    func applies() async throws {
        try await withPage(seeding: ["Work", "Home"]) { manager, appState, page in
            let home = manager.profiles[1].id
            let original = Defaults.DefaultValue.showOnHover
            appState.settings.visibility.showOnHover = !original
            try #require(appState.settings.displaySettings.spacingApplyMode == .writeOnly, "an apply must not restart apps")

            // An AppState that was never started has no layout engine, and the page says so in
            // an alert. A test must not open one, so a newer layout generation is issued as the
            // layout task starts, the way a second apply does, and the first one's report is dropped.
            @MainActor func supersedeNextLayoutReport() {
                withObservationTracking {
                    MainActor.assumeIsolated { _ = manager.layoutTask }
                } onChange: {
                    MainActor.assumeIsolated { _ = manager.beginLayoutApply(profileID: home) }
                }
            }
            supersedeNextLayoutReport()
            try manager.applyProfile(manager.loadProfile(id: manager.profiles[0].id), to: appState, relaunchesApps: false)
            await manager.layoutTask?.value
            try #require(!manager.layoutDidNotRun, "the report must be dropped before the page's Apply is pressed")
            appState.settings.visibility.showOnHover = !original

            supersedeNextLayoutReport()
            try page.press("Apply", at: 1)
            await page.settle { manager.activeProfileID == home && appState.settings.visibility.showOnHover == original }
            await manager.layoutTask?.value

            #expect(manager.activeProfileID == home)
            #expect(appState.settings.visibility.showOnHover == original, "the profile's saved setting is back")
            #expect(appState.settings.displaySettings.spacingApplyMode == .writeOnly)
            await page.settle { page.elements(role: .button, label: "Apply").count == 1 }
            #expect(page.elements(role: .button, label: "Apply").count == 1, "the active profile's row has no Apply button")
            #expect(page.texts().contains("Active"))
        }
    }

    @Test("A profile whose spacing would restart apps says so before it is applied")
    func warnsAboutRelaunch() async throws {
        try await withPage(seeding: ["Work"], prepare: { manager, appState in
            try #require(!appState.spacingManager.isOnDisk(offset: 5))
            try Self.setSpacingOffset(5, ofFirstProfileIn: manager)
            // Only read by the page here: nothing in this test applies a profile.
            appState.settings.displaySettings.spacingApplyMode = .relaunchApps
        }) { _, _, page in
            let warning = "Sets item spacing to 5, which quits and reopens every menu bar app"
            await page.settle { page.texts().contains(warning) }
            #expect(page.texts().contains(warning))
        }
    }

    @Test("With spacing only saved, the same profile shows no restart warning")
    func noWarningWhenSpacingIsOnlySaved() async throws {
        try await withPage(seeding: ["Work"], prepare: { manager, _ in
            try Self.setSpacingOffset(5, ofFirstProfileIn: manager)
        }) { _, _, page in
            await page.settle { page.texts().contains("What will change") }
            #expect(!page.texts().contains { $0.contains("quits and reopens") })
        }
    }
}
