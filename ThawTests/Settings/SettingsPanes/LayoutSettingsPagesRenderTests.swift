//
//  LayoutSettingsPagesRenderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw
import ThawUI

/// The Layout page and its sections, drawn off screen against an AppState that is never
/// started. The item list is seeded first, so the bars draw what is there and never preload
/// from the live bar. Settings are never set up with the AppState, so changing one only writes
/// the scratch defaults; nothing here hides an item, starts a stand-in or adds a folder icon.
@MainActor
@Suite("Layout settings rendering", .serialized, .scratchDefaults)
struct LayoutSettingsPagesRenderTests {
    private static let size = CGSize(width: 760, height: 2400)

    private typealias Page = OffscreenRender<AnyView>

    private func page(_ view: some View, appState: AppState) -> Page {
        OffscreenRender(
            AnyView(
                view
                    .environment(appState)
                    .environment(\.settingsPaneTitle, nil)
                    .frame(width: Self.size.width, height: Self.size.height)
            ),
            size: Self.size
        )
    }

    /// Waits until the page shows text, and returns what it shows.
    private func shownTexts(_ page: Page, containing text: String) async -> [String] {
        await page.settle { page.texts().contains { $0.contains(text) } }
        return page.texts()
    }

    private static func item(_ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.\(title)"), title: title, instanceIndex: 0),
            windowID: UInt32(x) + 1,
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 0, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static let visibleItem = item("Visible", x: 300)
    private static let hiddenItem = item("Hidden", x: 200)

    /// Seeds the item list, so nothing preloads from the live bar.
    private func seededAppState() -> AppState {
        let appState = AppState()
        appState.itemManager.itemCache[.visible] = [Self.visibleItem]
        appState.itemManager.itemCache[.hidden] = [Self.hiddenItem]
        return appState
    }

    // MARK: Page

    @Test("The Layout page draws its bars and opens each tab a search result asks for")
    func layoutPane() async throws {
        let appState = seededAppState()
        let page = page(MenuBarLayoutSettingsPane(itemManager: appState.itemManager), appState: appState)
        let texts = await shownTexts(page, containing: "Item arrangement")
        #expect(texts.contains { $0.contains("Hiding method") })
        #expect(texts.contains { $0.contains("Overflow and previews") })

        let disclosures: [(AppNavigationState.SettingsDisclosure, String)] = [
            (.layoutSpacers, "Spacers"),
            (.layoutAppleItems, "Replace Control Center items"),
            (.layoutOptions, "Item arrangement"),
        ]
        for (disclosure, text) in disclosures {
            appState.navigationState.requestedSettingsDisclosure = disclosure
            await page.settle { appState.navigationState.requestedSettingsDisclosure == nil }
            #expect(appState.navigationState.requestedSettingsDisclosure == nil, "the page takes \(disclosure)")
            let shown = await shownTexts(page, containing: text)
            #expect(shown.contains { $0.contains(text) }, "\(disclosure) shows \(text)")
        }
    }

    @Test("Without the bars, the tabs offer only Options and Spacers")
    func detailTabsWithoutBars() async {
        let appState = seededAppState()
        let page = page(
            LayoutDetailTabs(itemManager: appState.itemManager, canArrangeLayout: false, isHidingUnavailable: true),
            appState: appState
        )
        let texts = await shownTexts(page, containing: "Hiding unavailable")
        #expect(texts.contains { $0.contains("Hiding unavailable") })
        #expect(!texts.contains { $0.contains("Apple’s Items") })

        let fixed = self.page(
            LayoutDetailTabs(itemManager: appState.itemManager, canArrangeLayout: true, isHidingUnavailable: false, includesOptions: false, fixedTab: .appleItems),
            appState: appState
        )
        let fixedTexts = await shownTexts(fixed, containing: "Replace Control Center items")
        #expect(fixedTexts.contains { $0.contains("Replace Control Center items") }, "a fixed tab draws without the tab bar")
    }

    // MARK: Sections

    @Test("Section options show the custom divider controls, with and without an image")
    func sectionOptions() async throws {
        let appState = AppState()
        let layout = appState.settings.layout
        layout.sectionDividerStyle = .custom
        layout.customSectionDividerImage = nil
        let page = page(ThawForm { LayoutSectionOptions(settings: layout, isHidingUnavailable: false) }, appState: appState)
        let texts = await shownTexts(page, containing: "Divider image")
        #expect(texts.contains { $0.contains("Dividers show the chevron") })
        #expect(!page.elements(role: .button, label: "Choose Image…").isEmpty)

        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        layout.customSectionDividerImage = try #require(image.tiffRepresentation)
        let withImage = await shownTexts(page, containing: "Match the menu bar's appearance")
        #expect(withImage.contains { $0.contains("Shown between sections while they are open") })
        #expect(!page.elements(role: .button, label: "Change Image…").isEmpty)
    }

    @Test("The hiding method explains Standard and Native, and lists the macOS limitations")
    func hidingMethod() async {
        let appState = AppState()
        let layout = appState.settings.layout
        layout.enableNativeAppHiding = false
        let page = page(ThawForm { HidingMethodSection(settings: layout) }, appState: appState)
        let standard = await shownTexts(page, containing: "Known macOS 27 limitations")
        #expect(standard.contains { $0.contains("Hiding method") })

        let before = page.texts()
        layout.enableNativeAppHiding = true
        await page.settle { page.texts() != before }
        #expect(page.texts() != before, "choosing Native swaps in its own explanation")

        let list = self.page(PlatformLimitationsList(), appState: appState)
        let limitations = await shownTexts(list, containing: "Several items from one app")
        #expect(limitations.contains { $0.contains("The Native hiding method") })
    }

    @Test("Apple's items lists each replacement while the switch is on, and its boxes save")
    func controlCenterReplacements() async throws {
        let appState = AppState()
        let layout = appState.settings.layout
        layout.controlCenterReplacements.isOn = false
        let page = page(ThawForm { ControlCenterReplacementsSection(settings: layout) }, appState: appState)
        let off = await shownTexts(page, containing: "Replace Control Center items")
        #expect(!off.contains { $0 == "AirDrop" })

        layout.controlCenterReplacements.isOn = true
        await page.settle { page.elements().count { OffscreenAccessibility.role(of: $0) == .checkBox } > ControlCenterReplacements.listed.count }
        let boxes = page.elements().filter { OffscreenAccessibility.role(of: $0) == .checkBox }
        try #require(boxes.count == ControlCenterReplacements.listed.count + 1, "the switch and one box per item")

        // The first box after the switch is Focus.
        OffscreenAccessibility.press(boxes[1])
        await page.settle { !layout.controlCenterReplacements.isReplaced(.focus) }
        #expect(!layout.controlCenterReplacements.isReplaced(.focus))
        #expect(layout.controlCenterReplacements.isReplaced(.airDrop), "the others stay replaced")
    }

    @Test("The multi-select tip and the undo shortcuts draw")
    func tipAndUndoShortcuts() async throws {
        let appState = AppState()
        let page = page(
            VStack {
                LayoutMultiSelectTipView()
                Text("Undo host").modifier(LayoutUndoShortcuts(undoManager: appState.layoutUndo))
            },
            appState: appState
        )
        let texts = await shownTexts(page, containing: "Undo host")
        #expect(texts.contains("Undo host"))
    }

    // MARK: Groups

    @Test("Item groups say how to make one when there is none")
    func groupsEmpty() async {
        let appState = seededAppState()
        let page = page(ThawForm { MenuBarLayoutGroupsSection() }, appState: appState)
        let texts = await shownTexts(page, containing: "No item groups")
        #expect(texts.contains { $0.contains("No item groups") })
    }

    @Test("A group lists its members, renames, collapses, drops a member and ungroups")
    func groupRows() async throws {
        let appState = seededAppState()
        let manager = appState.itemGroupManager
        let gone = Self.item("Gone", x: 500)
        _ = try #require(manager.createGroup(name: "Work", items: [Self.visibleItem, Self.hiddenItem, gone]))
        let page = page(ThawForm { MenuBarLayoutGroupsSection() }, appState: appState)

        let texts = await shownTexts(page, containing: "not running")
        #expect(texts.contains { $0.contains("Groups always move and hide together") })
        #expect(texts.contains { $0.contains(gone.uniqueIdentifier) }, "a quit app's member shows its identifier")

        let field = try #require(page.views(NSTextField.self).first { $0.isEditable })
        page.type("Office", into: field)
        page.submit(field)
        await page.settle { manager.groupSet.groups.first?.name == "Office" }
        #expect(manager.groupSet.groups.first?.name == "Office")

        try page.press("Collapse")
        await page.settle { manager.groupSet.groups.first?.isCollapsed == true }
        #expect(manager.groupSet.groups.first?.isCollapsed == true)
        try page.press("Expand")
        await page.settle { manager.groupSet.groups.first?.isCollapsed == false }
        #expect(manager.groupSet.groups.first?.isCollapsed == false)

        try page.press("Remove \(gone.uniqueIdentifier) from group")
        await page.settle { manager.groupSet.groups.first?.memberIdentifiers.contains(gone.uniqueIdentifier) == false }
        #expect(manager.groupSet.groups.first?.memberIdentifiers.contains(gone.uniqueIdentifier) == false, "an absent member is removed from the store")

        try page.press("Ungroup")
        await page.settle { manager.groupSet.groups.isEmpty }
        #expect(manager.groupSet.groups.isEmpty)
    }
}
