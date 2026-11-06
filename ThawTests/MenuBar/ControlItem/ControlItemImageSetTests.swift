//
//  ControlItemImageSetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// The icons offered for the Thaw icon, and the sections built on an AppState that was never set up.
@MainActor
@Suite("Control item icons and sections", .serialized, .scratchDefaults)
struct ControlItemImageSetTests {
    @Test("Every offered icon draws in both states")
    func offeredIconsResolve() {
        let appState = AppState()
        for set in ControlItemImageSet.userSelectableThawIcons {
            #expect(set.hidden.nsImage(for: appState) != nil, "\(set.name.rawValue) hidden")
            #expect(set.visible.nsImage(for: appState) != nil, "\(set.name.rawValue) visible")
        }
        #expect(ControlItemImageSet.defaultThawIcon.hidden.nsImage(for: appState) != nil)
    }

    @Test("Each offered icon has its own name and two different images")
    func offeredIconsAreDistinct() {
        let icons = ControlItemImageSet.userSelectableThawIcons
        #expect(Set(icons.map(\.name)).count == icons.count)
        #expect(icons.allSatisfy { $0.hidden != $0.visible })
        #expect(!icons.contains { $0.name == .custom })
        #expect(icons.contains(ControlItemImageSet.defaultThawIcon))
    }

    @Test("A single-image set shows the same image in both states")
    func singleImageSet() {
        let set = ControlItemImageSet(name: .custom, image: .symbol("star"))
        #expect(set.hidden == set.visible)
        #expect(set.id == ControlItemImageSet(name: .custom, image: .symbol("star")).id)
    }

    @Test("Icon names keep the raw values saved settings use")
    func persistedNames() throws {
        #expect(ControlItemImageSet.Name(rawValue: "Ice Cube") == .iceCube)
        #expect(ControlItemImageSet.Name(rawValue: "Chevron (Down)") == .chevronDown)
        let data = try JSONEncoder().encode(ControlItemImageSet.defaultThawIcon)
        #expect(try JSONDecoder().decode(ControlItemImageSet.self, from: data) == ControlItemImageSet.defaultThawIcon)
    }

    @Test("Sections that were never set up read as hidden and have no hotkey")
    func sectionsBeforeSetup() {
        let visible = MenuBarSection(name: .visible)
        let hidden = MenuBarSection(name: .hidden)
        #expect(hidden.isHidden)
        #expect(hidden.isEnabled)
        #expect(hidden.isToggleEnabled)
        #expect(hidden.hotkey == nil)
        #expect(visible.hotkey == nil)
        #expect(!hidden.controlItem.sectionName.rawValue.isEmpty)
        #expect(hidden.controlItem.isSectionDivider)
        #expect(!visible.controlItem.isSectionDivider)
        #expect(visible.controlItem.sectionName == .visible)
    }

    @Test("A set-up app state's sections expose their hotkeys")
    func sectionHotkeys() throws {
        let appState = AppState()
        let hidden = try #require(appState.menuBarManager.section(withName: .hidden))
        // The manager's sections are never set up here, so they hold no app state.
        #expect(hidden.hotkey == nil)
        #expect(appState.settings.hotkeys.hotkey(withAction: .toggleHiddenSection) != nil)
    }

    @Test("Hiding and toggling a section with no manager changes nothing")
    func hideWithoutManager() {
        let section = MenuBarSection(name: .hidden)
        section.hide()
        section.toggle()
        section.show(triggeredByHotkey: true)
        section.updateControlItemState()
        #expect(section.isHidden)
        #expect(section.desiredState == .hideSection)
    }

    @Test("The appearance renderer records a state only when it drew it")
    func stateAppearanceUpdates() {
        let updates = ControlItem.StateAppearanceUpdates()
        #expect(!updates.apply(state: .showSection, stateChangeOnly: false) { false })
        #expect(updates.apply(state: .showSection, stateChangeOnly: true) { true })
        #expect(!updates.apply(state: .showSection, stateChangeOnly: true) { true })
        #expect(updates.apply(state: .showSection, stateChangeOnly: false) { true })
        #expect(updates.apply(state: .hideSection, stateChangeOnly: true) { true })
    }
}
