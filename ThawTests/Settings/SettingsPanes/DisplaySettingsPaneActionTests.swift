//
//  DisplaySettingsPaneActionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// The Displays page drawn off screen and worked through its own controls, against an AppState
/// that is never started, profiles in a throwaway folder and one saved display that is not
/// connected. Nothing here opens an alert, a panel or a menu: the pages' own alerts only show in
/// a visible window, so what they would ask is checked through the page's confirmation messages
/// and through the write-only path, which saves without asking.
@MainActor
@Suite("Displays page actions", .serialized, .scratchDefaults)
struct DisplaySettingsPaneActionTests {
    private static let size = CGSize(width: 760, height: 2400)
    private static let studio = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

    private typealias Page = OffscreenRender<AnyView>

    /// The page and what it shows, with the saved display "Studio" selected so the page does not
    /// depend on which displays this Mac has.
    private struct World {
        let appState: AppState
        let settings: DisplaySettingsManager
        let manager: ProfileManager
        let directory: URL
        let page: Page
    }

    /// Draws the page over a folder seeded with the named profiles, the first of them active, and
    /// waits for it to show. Spacing is only ever written, so nothing a test does can restart an app.
    private func withWorld(
        profiles names: [String] = [],
        studioOffset: Double = 4,
        _ body: (World) async throws -> Void
    ) async throws {
        let directory = try ProfileTestDirectory.make(seeding: names)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appState = ProfileManager.$directoryOverride.withValue(directory) { AppState() }
        let manager = appState.profileManager
        manager.activeProfileID = manager.profiles.first?.id
        let settings = appState.settings.displaySettings
        appState.spacingManager.spacingApplyMode = .writeOnly
        settings.spacingApplyMode = .writeOnly
        settings.knownDisplays[Self.studio] = KnownDisplay(name: "Studio", hasNotch: false)
        settings.configurations[Self.studio] = DisplayThawBarConfiguration.defaultConfiguration
            .withItemSpacingOffset(studioOffset)
        let page = OffscreenRender(
            AnyView(
                DisplaySettingsPane(displaySettings: settings, selectedDisplayID: Self.studio)
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
        await page.settle { (try? page.pixels())?.contains { $0 != 0 } == true }
        try await body(World(appState: appState, settings: settings, manager: manager, directory: directory, page: page))
    }

    private func showTab(_ section: String, in world: World) async {
        world.appState.navigationState.requestedSettingsSection = section
        await world.page.settle { world.appState.navigationState.requestedSettingsSection == nil }
    }

    private func sliders(in page: Page) -> [NSObject] {
        page.elements().filter { OffscreenAccessibility.role(of: $0) == .slider }
    }

    private func checkBoxes(in page: Page) -> [NSObject] {
        page.elements().filter { OffscreenAccessibility.role(of: $0) == .checkBox }
    }

    /// Moves a slider one step up, as VoiceOver's adjust does.
    private func increment(_ slider: NSObject) {
        _ = slider.perform(NSSelectorFromString("accessibilityPerformIncrement"))
    }

    private func isEnabled(_ element: NSObject) -> Bool {
        (element.value(forKey: "accessibilityEnabled") as? Bool) == true
    }

    private func has(_ label: String, in page: Page) -> Bool {
        !page.elements(role: .button, label: label).isEmpty
    }

    private func savedOffset(_ world: World) -> Double {
        world.settings.configuration(forUUID: Self.studio).itemSpacingOffset
    }

    private func profileOffset(_ name: String, in world: World) throws -> Double? {
        let meta = try #require(world.manager.profiles.first { $0.name == name })
        return try world.manager.loadProfile(id: meta.id).displayConfigurations[Self.studio]?.itemSpacingOffset
    }

    @Test("A saved display that is not connected shows its name, badges and the buttons for it")
    func disconnectedDisplayHeader() async throws {
        try await withWorld { world in
            let texts = world.page.texts()
            #expect(texts.contains("Studio"))
            #expect(texts.contains("Disconnected"))
            #expect(texts.contains("Customized"), "its spacing differs from the template")
            #expect(has("Use Template", in: world.page))
            #expect(has("Forget Display…", in: world.page))
            #expect(!has("Reapply Spacing", in: world.page), "only the display that has the menu bar can reapply")

            world.settings.configurations[Self.studio] = world.settings.globalConfiguration
            await world.page.settle { !world.page.texts().contains("Customized") }
            #expect(!world.page.texts().contains("Customized"), "matching the template takes the badge away")
            #expect(!has("Use Template", in: world.page))
            #expect(has("Forget Display…", in: world.page), "a display that is gone can still be forgotten")

            // Forgetting asks first, in an alert this window never shows, so the display stays.
            try world.page.press("Forget Display…")
            #expect(world.settings.displays.contains { $0.id == Self.studio }, "nothing is forgotten before the answer")
        }
    }

    @Test("A spacing slider move waits as a draft until Apply, and Discard puts the saved value back")
    func spacingDraft() async throws {
        try await withWorld { world in
            let page = world.page
            #expect(sliders(in: page).first.flatMap { OffscreenAccessibility.label(of: $0) } == "4")
            #expect(!has("Apply", in: page))

            increment(try #require(sliders(in: page).first))
            await page.settle { has("Apply", in: page) }
            #expect(has("Apply", in: page) && has("Discard", in: page), "a draft shows the strip")
            #expect(OffscreenAccessibility.label(of: try #require(sliders(in: page).first)) == "6")
            #expect(savedOffset(world) == 4, "dragging saves nothing")
            #expect(page.texts().contains("Apps pick up the new spacing the next time they start"), "write-only mode promises no relaunch")

            try page.press("Discard")
            await page.settle { !has("Apply", in: page) }
            #expect(!has("Apply", in: page))
            #expect(OffscreenAccessibility.label(of: try #require(sliders(in: page).first)) == "4")
            #expect(savedOffset(world) == 4)

            increment(try #require(sliders(in: page).first))
            await page.settle { has("Apply", in: page) }
            try page.press("Apply")
            await page.settle { !has("Apply", in: page) }
            #expect(savedOffset(world) == 6, "Apply saves the draft")
            #expect(OffscreenAccessibility.label(of: try #require(sliders(in: page).first)) == "6")
        }
    }

    @Test("When apps restart for a new spacing, the draft strip says so")
    func draftNoticeWhenRestarting() async throws {
        try await withWorld { world in
            world.settings.spacingApplyMode = .relaunchApps
            let page = world.page
            increment(try #require(sliders(in: page).first))
            await page.settle { has("Apply", in: page) }
            #expect(page.texts().contains("Applying relaunches apps with menu bar items"))
            #expect(!page.texts().contains("Apps pick up the new spacing the next time they start"))
            try page.press("Discard")
            await page.settle { !has("Apply", in: page) }
            #expect(savedOffset(world) == 4)
        }
    }

    @Test("Reset saves the default spacing, and is out of reach once spacing is the default")
    func resetSpacing() async throws {
        try await withWorld { world in
            let page = world.page
            let reset = "Reset to the default spacing"
            try page.press(reset)
            await page.settle { savedOffset(world) == 0 }
            #expect(savedOffset(world) == 0)
            await page.settle { OffscreenAccessibility.label(of: sliders(in: page)[0]) == "Default" }
            #expect(OffscreenAccessibility.label(of: sliders(in: page)[0]) == "Default")
            let button = try #require(page.elements(role: .button, label: reset).first)
            #expect(!isEnabled(button))
        }
    }

    @Test("Use Template copies every template setting onto the display, spacing included")
    func useTemplate() async throws {
        try await withWorld { world in
            world.settings.globalConfiguration = DisplayThawBarConfiguration.defaultConfiguration
                .withUseThawBar(true).withThawBarLayout(.grid).withGridColumns(5).withItemSpacingOffset(2)
            world.settings.configurations[Self.studio] = DisplayThawBarConfiguration.defaultConfiguration
                .withItemSpacingOffset(4).withUseThawBarForAlwaysHidden(true)
            await world.page.settle { has("Use Template", in: world.page) }

            try world.page.press("Use Template")
            await world.page.settle { savedOffset(world) == 2 }
            #expect(world.settings.configuration(forUUID: Self.studio) == world.settings.globalConfiguration)
            await world.page.settle { !has("Use Template", in: world.page) }
            #expect(!world.page.texts().contains("Customized"))
        }
    }

    @Test("With a profile active, an applied spacing is saved to that profile only, or to every profile")
    func spacingSavesToProfiles() async throws {
        try await withWorld(profiles: ["Work", "Home"]) { world in
            let page = world.page
            increment(try #require(sliders(in: page).first))
            await page.settle { has("Apply", in: page) }
            try page.press("Apply")
            await page.settle { (try? profileOffset("Work", in: world)) == 6 }
            #expect(try profileOffset("Work", in: world) == 6, "the active profile keeps the spacing")
            #expect(try profileOffset("Home", in: world) != 6, "the other profile is left alone")

            let everyProfile = try #require(checkBoxes(in: page).first)
            OffscreenAccessibility.press(everyProfile)
            await page.settle { world.settings.unconfirmedSpacingProfileScope == .allProfiles }
            #expect(world.settings.unconfirmedSpacingProfileScope == .allProfiles)

            increment(try #require(sliders(in: page).first))
            await page.settle { has("Apply", in: page) }
            try page.press("Apply")
            await page.settle { (try? profileOffset("Home", in: world)) == 8 }
            #expect(try profileOffset("Work", in: world) == 8)
            #expect(try profileOffset("Home", in: world) == 8, "every profile keeps it")
            #expect(savedOffset(world) == 8)
        }
    }

    @Test("A spacing that cannot be saved to the profile goes back to the value it had")
    func spacingRollsBack() async throws {
        try await withWorld(profiles: ["Work"]) { world in
            let id = try #require(world.manager.activeProfileID)
            try FileManager.default.removeItem(at: world.directory.appendingPathComponent("\(id.uuidString).json"))
            let page = world.page
            increment(try #require(sliders(in: page).first))
            await page.settle { has("Apply", in: page) }
            try page.press("Apply")
            await page.settle { OffscreenAccessibility.label(of: sliders(in: page)[0]) == "4" && !has("Apply", in: page) }
            #expect(savedOffset(world) == 4, "the unsaved spacing is rolled back")
            #expect(OffscreenAccessibility.label(of: try #require(sliders(in: page).first)) == "4")
        }
    }

    @Test("The notice under Spacing follows the choice, and the profile switch appears only when nothing asks")
    func spacingChoiceNotices() async throws {
        try await withWorld { world in
            for choice in SpacingApplyChoice.allCases {
                world.settings.spacingApplyMode = choice.mode
                if let confirms = choice.confirms {
                    world.settings.confirmSpacingRelaunch = confirms
                }
                let notice = String(localized: choice.relaunchNotice.message)
                // The page says the notice's title and message as one text.
                let showsNotice = { world.page.texts().contains { $0.hasSuffix(notice) } }
                await world.page.settle(until: showsNotice)
                #expect(showsNotice(), "\(choice) shows its own notice")
                let hasSwitch = !checkBoxes(in: world.page).isEmpty
                #expect(hasSwitch == (choice != .askFirst), "\(choice) shows the profile switch only when nothing asks")
            }
        }
    }

    @Test("Template edits stay in the template, and Apply to all displays is out of reach when every display already matches")
    func templateTab() async throws {
        try await withWorld { world in
            let page = world.page
            let apply = "Apply template to all displays"
            await showTab("Template for new displays", in: world)
            await page.settle { has(apply, in: page) }
            #expect(isEnabled(try #require(page.elements(role: .button, label: apply).first)), "Studio differs from the template")
            #expect(page.texts().contains { $0.contains("the next time they start") }, "write-only mode promises no relaunch")

            world.settings.configurations = [:]
            await page.settle { !isEnabled(page.elements(role: .button, label: apply)[0]) }
            #expect(!isEnabled(try #require(page.elements(role: .button, label: apply).first)), "nothing to copy")

            let before = world.settings.globalConfiguration
            increment(try #require(sliders(in: page).first))
            await page.settle { world.settings.globalConfiguration.itemSpacingOffset == before.itemSpacingOffset + 2 }
            #expect(world.settings.globalConfiguration.itemSpacingOffset == before.itemSpacingOffset + 2, "the slider stages spacing in the template at once")
            #expect(world.settings.configurations.isEmpty, "no display is touched")

            OffscreenAccessibility.press(try #require(checkBoxes(in: page).first))
            await page.settle { world.settings.globalConfiguration.useThawBar != before.useThawBar }
            #expect(world.settings.globalConfiguration.useThawBar == !before.useThawBar, "the switch edits the template")
            #expect(world.settings.configurations.isEmpty)
        }
    }

    @Test("The Wide Displays switch turns the rule on and shows its width, which moves a step at a time")
    func wideDisplaysTab() async throws {
        try await withWorld { world in
            let page = world.page
            let rule = world.settings.wideDisplayRule
            await showTab("Wide displays", in: world)
            await page.settle { !checkBoxes(in: page).isEmpty }
            #expect(sliders(in: page).isEmpty, "the width is hidden while the rule is off")

            OffscreenAccessibility.press(try #require(checkBoxes(in: page).first))
            await page.settle { rule.isEnabled }
            #expect(rule.isEnabled)
            await page.settle { !sliders(in: page).isEmpty }
            let width = rule.minimumWidth
            increment(try #require(sliders(in: page).first))
            await page.settle { rule.minimumWidth != width }
            #expect(rule.minimumWidth == width + 160)
        }
    }

    @Test("The search sections map onto the tab that holds them")
    func tabForSection() {
        #expect(DisplaysTab(section: "Menu bar item spacing") == .spacing)
        #expect(DisplaysTab(section: "Template for new displays") == .template)
        for section in ["Space indicator", "This Space", "All Spaces"] {
            #expect(DisplaysTab(section: section) == .spaces)
        }
        #expect(DisplaysTab(section: "Wide displays") == .wideDisplays)
        #expect(DisplaysTab(section: "Something else") == nil)
    }

    @Test("The confirmation messages say who is restarted and where the spacing is saved")
    func confirmationMessages() async throws {
        try await withWorld { world in
            let pane = DisplaySettingsPane(displaySettings: world.settings)
            let active = DisplaySettingsPane.PendingSpacingApply(
                displayID: Self.studio, displayName: "Studio", offset: 6, isActiveDisplay: true,
                activeProfileID: UUID(), activeProfileName: "Work"
            )
            let activeMessage = pane.spacingConfirmationMessage(for: active)
            #expect(activeMessage.contains("relaunches every app with a menu bar item"))
            #expect(activeMessage.contains("“Work”"))

            let other = DisplaySettingsPane.PendingSpacingApply(
                displayID: Self.studio, displayName: "Studio", offset: 6, isActiveDisplay: false,
                activeProfileID: nil, activeProfileName: nil
            )
            #expect(pane.spacingConfirmationMessage(for: other).isEmpty, "another display restarts nothing and has no profile to choose")

            let global = DisplaySettingsPane.PendingGlobalApply(displayCount: 2, activeProfileID: UUID(), activeProfileName: "Work")
            let writeOnly = pane.globalConfirmationMessage(for: global)
            #expect(writeOnly.contains("apps are not restarted"))
            #expect(writeOnly.contains("“Work”"))

            world.settings.spacingApplyMode = .relaunchApps
            let relaunch = pane.globalConfirmationMessage(for: .init(displayCount: 1, activeProfileID: nil, activeProfileName: nil))
            #expect(relaunch.contains("Thaw will relaunch each app"))
            #expect(!relaunch.contains("“"), "with no profile active there is no profile to choose")
        }
    }
}
