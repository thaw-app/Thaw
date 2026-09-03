//
//  MenuBarSpacerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import Foundation
import Testing

@Suite("Menu bar spacers")
struct MenuBarSpacerTests {
    @Test("init clamps width into the supported range")
    func initClampsWidth() {
        #expect(MenuBarSpacer(width: 1).width == MenuBarSpacer.minWidth)
        #expect(MenuBarSpacer(width: 10000).width == MenuBarSpacer.maxWidth)
        #expect(MenuBarSpacer(width: 40).width == 40)
    }

    @Test("the default width lies within the bounds")
    func defaultWidthIsWithinBounds() {
        let spacer = MenuBarSpacer()
        #expect(spacer.width == MenuBarSpacer.defaultWidth)
        #expect((MenuBarSpacer.minWidth ... MenuBarSpacer.maxWidth).contains(spacer.width))
    }

    @Test("spacers survive a Codable round trip")
    func codableRoundTrip() throws {
        let spacers = [MenuBarSpacer(width: 24), MenuBarSpacer(width: 120)]
        let data = try JSONEncoder().encode(spacers)
        let decoded = try JSONDecoder().decode([MenuBarSpacer].self, from: data)
        #expect(decoded == spacers)
    }

    @Test("a user spacer tag is not a control item")
    func userSpacerTagIsNotControlItem() {
        // User-created spacers must stay draggable, reorderable, and
        // concealable — control items are none of those.
        let id = UUID()
        let tag = MenuBarItemTag(
            namespace: .thaw,
            title: "\(MenuBarSpacerManager.autosavePrefix)\(id.uuidString)"
        )

        #expect(!tag.isControlItem)
    }

    @Test("a section divider spacer tag is still a control item")
    func sectionDividerSpacerTagIsStillControlItem() {
        // The section-divider spacers Thaw synthesizes for section hiding
        // remain control items.
        let tag = MenuBarItemTag(
            namespace: .thaw,
            title: "\(ControlItem.Identifier.visible.rawValue).Spacer.0"
        )

        #expect(tag.isControlItem)
    }

    @Test("isSpacerTag rejects divider spacers and foreign items")
    func isSpacerTagRejectsDividerSpacersAndForeignItems() {
        let userSpacer = MenuBarItemTag(
            namespace: .thaw,
            title: "\(MenuBarSpacerManager.autosavePrefix)\(UUID().uuidString)"
        )
        let divider = MenuBarItemTag(
            namespace: .thaw,
            title: "\(ControlItem.Identifier.hidden.rawValue).Spacer.1"
        )
        let foreign = MenuBarItemTag(namespace: .systemUIServer, title: "Item-0")

        #expect(MenuBarSpacerManager.isSpacerTag(userSpacer))
        #expect(!MenuBarSpacerManager.isSpacerTag(divider))
        #expect(!MenuBarSpacerManager.isSpacerTag(foreign))
    }
}
