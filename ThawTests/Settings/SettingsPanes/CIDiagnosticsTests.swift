//
//  CIDiagnosticsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// TEMPORARY, never merged. CI shows only which tests passed, so each test here asks one yes or no
/// question about what the Profiles page offers, and the pattern of passes says what differs on the runner.
@MainActor
@Suite("CI diagnostics", .serialized, .scratchDefaults)
struct CIDiagnosticsTests {
    private static let size = CGSize(width: 760, height: 2400)
    private typealias Page = OffscreenRender<AnyView>

    private func withPage(
        seeding names: [String] = ["Work", "Home"],
        prepare: (ProfileManager, AppState) throws -> Void = { _, _ in /* Nothing to set up. */ },
        _ body: (ProfileManager, AppState, Page) async throws -> Void
    ) async throws {
        let tmp = try ProfileTestDirectory.make(seeding: names)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let manager = ProfileManager(profilesDirectory: tmp)
        let appState = AppState()
        let offset = (DisplaySettingsManager.currentSystemSpacing() ?? 16) - 16
        appState.spacingManager.offset = offset
        appState.spacingManager.spacingApplyMode = .writeOnly
        appState.settings.displaySettings.spacingApplyMode = .writeOnly
        try prepare(manager, appState)
        let page = OffscreenRender(
            AnyView(
                ProfileSettingsPane(profileManager: manager)
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
        await page.settle { (try? page.pixels())?.contains { $0 != 0 } == true }
        try await body(manager, appState, page)
    }

    private func row(_ name: String, in page: Page) -> NSObject? {
        page.elements().first {
            OffscreenAccessibility.role(of: $0) == .button
                && OffscreenAccessibility.label(of: $0)?.hasPrefix(name + ",") == true
        }
    }

    private func fields(in page: Page) -> [NSTextField] {
        page.views(NSTextField.self).filter(\.isEditable)
    }

    @Test("Q01 the page shows a row button for Work")
    func q01RowWork() async throws {
        try await withPage { _, _, page in #expect(row("Work", in: page) != nil) }
    }

    @Test("Q02 the page shows a row button for Home")
    func q02RowHome() async throws {
        try await withPage { _, _, page in #expect(row("Home", in: page) != nil) }
    }

    @Test("Q03 the page shows the text Profiles")
    func q03TextProfiles() async throws {
        try await withPage { _, _, page in #expect(page.texts().contains("Profiles")) }
    }

    @Test("Q04 the page has an undo manager")
    func q04UndoManager() async throws {
        try await withPage { _, _, page in #expect(page.host.undoManager != nil) }
    }

    @Test("Q05 the hosting view has a window")
    func q05Window() async throws {
        try await withPage { _, _, page in #expect(page.host.window != nil) }
    }

    @Test("Q06 a context menu comes back over the Work row")
    func q06ContextMenu() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            _ = try page.contextMenu(over: work)
        }
    }

    @Test("Q07 that context menu has Rename")
    func q07MenuHasRename() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            #expect(try page.contextMenu(over: work).indexOfItem(withTitle: "Rename") >= 0)
        }
    }

    @Test("Q08 that context menu has Duplicate")
    func q08MenuHasDuplicate() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            #expect(try page.contextMenu(over: work).indexOfItem(withTitle: "Duplicate") >= 0)
        }
    }

    @Test("Q09 that context menu has Export")
    func q09MenuHasExport() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            #expect(try page.contextMenu(over: work).indexOfItem(withTitle: "Export…") >= 0)
        }
    }

    @Test("Q10 Rename leaves two editable text fields")
    func q10RenameTwoFields() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            try page.contextMenu(over: work).choose("Rename")
            await page.settle(within: .seconds(5)) { fields(in: page).count == 2 }
            #expect(fields(in: page).count == 2)
        }
    }

    @Test("Q11 Rename leaves one or more editable text fields")
    func q11RenameSomeFields() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            try page.contextMenu(over: work).choose("Rename")
            await page.settle(within: .seconds(5)) { fields(in: page).count >= 1 }
            #expect(fields(in: page).count >= 1)
        }
    }

    @Test("Q12 Rename shows a Done button")
    func q12RenameDone() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            try page.contextMenu(over: work).choose("Rename")
            await page.settle(within: .seconds(5)) { !page.elements(role: .button, label: "Done").isEmpty }
            #expect(!page.elements(role: .button, label: "Done").isEmpty)
        }
    }

    @Test("Q13 the rename field starts with the current name")
    func q13RenameStartsWithName() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            try page.contextMenu(over: work).choose("Rename")
            await page.settle(within: .seconds(5)) { fields(in: page).count >= 1 }
            #expect(fields(in: page).first?.stringValue == "Work")
        }
    }

    @Test("Q14 typing a new name and pressing Done renames the profile")
    func q14RenameSaves() async throws {
        try await withPage { manager, _, page in
            let work = try #require(row("Work", in: page))
            try page.contextMenu(over: work).choose("Rename")
            await page.settle(within: .seconds(5)) { fields(in: page).count >= 1 }
            page.type("Office", into: try #require(fields(in: page).first))
            try page.press("Done")
            #expect(manager.profiles.map(\.name) == ["Office", "Home"])
        }
    }

    @Test("Q15 Rename registers an undo step")
    func q15RenameUndo() async throws {
        try await withPage { _, _, page in
            let work = try #require(row("Work", in: page))
            try page.contextMenu(over: work).choose("Rename")
            await page.settle(within: .seconds(5)) { fields(in: page).count >= 1 }
            page.type("Office", into: try #require(fields(in: page).first))
            try page.press("Done")
            #expect(page.host.undoManager?.undoActionName == "Rename Profile")
        }
    }

    private func popUpValues(in page: Page) -> [String] {
        page.elements()
            .filter { OffscreenAccessibility.role(of: $0) == .popUpButton }
            .compactMap { OffscreenAccessibility.string("accessibilityValue", of: $0) }
    }

    @Test("Q16 the Down Arrow moves to the next profile, as the real test does it")
    func q16ArrowKeys() async throws {
        try await withPage(prepare: { manager, _ in
            manager.setAssociatedDisplay(uuid: "DISPLAY", displayName: "Studio", forProfileID: manager.profiles[1].id)
        }) { _, _, page in
            let window = try #require(page.host.window)
            let showsHome = { popUpValues(in: page).contains("Studio · Disconnected") }
            window.makeFirstResponder(page.host)
            for _ in 0 ..< 8 where !showsHome() {
                window.selectNextKeyView(nil)
                await page.settle(within: .milliseconds(200)) { false }
                let characters = String(UnicodeScalar(NSDownArrowFunctionKey)!)
                let event = try #require(NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 125
                ))
                window.firstResponder?.keyDown(with: event)
                await page.settle(within: .milliseconds(300)) { showsHome() }
            }
            #expect(showsHome())
        }
    }

    @Test("Q26 the pickers read the display saved on the selected profile")
    func q26PickerShowsSavedDisplay() async throws {
        try await withPage(prepare: { manager, _ in
            manager.setAssociatedDisplay(uuid: "DISPLAY", displayName: "Studio", forProfileID: manager.profiles[0].id)
        }) { _, _, page in
            await page.settle(within: .seconds(10)) { popUpValues(in: page).contains("Studio · Disconnected") }
            #expect(popUpValues(in: page).contains("Studio · Disconnected"))
        }
    }

    @Test("Q27 the pop-up buttons expose any accessibility value at all")
    func q27PopUpHasValue() async throws {
        try await withPage { _, _, page in
            await page.settle(within: .seconds(10)) { !popUpValues(in: page).isEmpty }
            #expect(!popUpValues(in: page).isEmpty)
        }
    }

    @Test("Q17 each profile row has an Apply button")
    func q17TwoApplyButtons() async throws {
        try await withPage { _, _, page in #expect(page.elements(role: .button, label: "Apply").count == 2) }
    }

    @Test("Q18 pressing the second Apply makes that profile active")
    func q18ApplyMakesActive() async throws {
        try await withPage { manager, _, page in
            let home = manager.profiles[1].id
            try page.press("Apply", at: 1)
            await page.settle(within: .seconds(10)) { manager.activeProfileID == home }
            #expect(manager.activeProfileID == home)
        }
    }

    @Test("Q19 the page shows What will change")
    func q19WhatWillChange() async throws {
        try await withPage { _, _, page in
            await page.settle(within: .seconds(10)) { page.texts().contains("What will change") }
            #expect(page.texts().contains("What will change"))
        }
    }

    @Test("Q20 a profile with new spacing shows the restart warning, set up as the real test does")
    func q20RestartWarning() async throws {
        try await withPage(seeding: ["Work"], prepare: { manager, appState in
            var profile = try manager.loadProfile(id: manager.profiles[0].id)
            profile.globalDisplayConfiguration = profile.globalDisplayConfiguration.withItemSpacingOffset(5)
            profile.displayConfigurations = [:]
            try manager.replaceProfile(profile)
            appState.settings.displaySettings.spacingApplyMode = .relaunchApps
        }) { _, _, page in
            await page.settle(within: .seconds(10)) { page.texts().contains { $0.contains("quits and reopens") } }
            #expect(page.texts().contains { $0.contains("quits and reopens") })
        }
    }

    @Test("Q21 the page offers at least two pop-up buttons for the selected profile")
    func q21TwoPopUps() async throws {
        try await withPage { _, _, page in
            await page.settle(within: .seconds(10)) {
                page.elements().filter { OffscreenAccessibility.role(of: $0) == .popUpButton }.count >= 2
            }
            #expect(page.elements().filter { OffscreenAccessibility.role(of: $0) == .popUpButton }.count >= 2)
        }
    }

    @Test("Q22 the page offers at least one pop-up button")
    func q22SomePopUp() async throws {
        try await withPage { _, _, page in
            await page.settle(within: .seconds(10)) {
                page.elements().contains { OffscreenAccessibility.role(of: $0) == .popUpButton }
            }
            #expect(page.elements().contains { OffscreenAccessibility.role(of: $0) == .popUpButton })
        }
    }

    @Test("Q23 the pop-up buttons read None")
    func q23PopUpValues() async throws {
        try await withPage { _, _, page in
            await page.settle(within: .seconds(10)) {
                page.elements().filter { OffscreenAccessibility.role(of: $0) == .popUpButton }
                    .compactMap { OffscreenAccessibility.string("accessibilityValue", of: $0) } == ["None", "None"]
            }
            let values = page.elements().filter { OffscreenAccessibility.role(of: $0) == .popUpButton }
                .compactMap { OffscreenAccessibility.string("accessibilityValue", of: $0) }
            #expect(values == ["None", "None"])
        }
    }

    @Test("Q24 the page has a segmented control for Update with Current Setup")
    func q24SegmentedControl() async throws {
        try await withPage { _, _, page in
            await page.settle(within: .seconds(10)) { !page.views(NSSegmentedControl.self).isEmpty }
            #expect(!page.views(NSSegmentedControl.self).isEmpty)
        }
    }

    @Test("Q25 saving the current setup from the name field adds a profile")
    func q25SaveCurrent() async throws {
        try await withPage(seeding: []) { manager, _, page in
            let field = try #require(fields(in: page).first)
            page.type("Desk", into: field)
            await page.settle(within: .seconds(5)) { (try? page.press("Save Current")) != nil && !manager.profiles.isEmpty }
            #expect(manager.profiles.map(\.name) == ["Desk"])
        }
    }
}
