//
//  MenuBarSpacerTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import Thaw
import XCTest

final class MenuBarSpacerTests: XCTestCase {
    func testInitClampsWidth() {
        XCTAssertEqual(MenuBarSpacer(width: 1).width, MenuBarSpacer.minWidth)
        XCTAssertEqual(MenuBarSpacer(width: 10_000).width, MenuBarSpacer.maxWidth)
        XCTAssertEqual(MenuBarSpacer(width: 40).width, 40)
    }

    func testDefaultWidthIsWithinBounds() {
        let spacer = MenuBarSpacer()
        XCTAssertEqual(spacer.width, MenuBarSpacer.defaultWidth)
        XCTAssertTrue((MenuBarSpacer.minWidth ... MenuBarSpacer.maxWidth).contains(spacer.width))
    }

    func testCodableRoundTrip() throws {
        let spacers = [MenuBarSpacer(width: 24), MenuBarSpacer(width: 120)]
        let data = try JSONEncoder().encode(spacers)
        let decoded = try JSONDecoder().decode([MenuBarSpacer].self, from: data)
        XCTAssertEqual(decoded, spacers)
    }

    func testUserSpacerTagIsNotControlItem() {
        // User-created spacers must stay draggable, reorderable, and
        // concealable — control items are none of those.
        let id = UUID()
        let tag = MenuBarItemTag(
            namespace: .thaw,
            title: "\(MenuBarSpacerManager.autosavePrefix)\(id.uuidString)"
        )

        XCTAssertFalse(tag.isControlItem)
    }

    func testSectionDividerSpacerTagIsStillControlItem() {
        // The section-divider spacers Thaw synthesizes for section hiding
        // remain control items.
        let tag = MenuBarItemTag(
            namespace: .thaw,
            title: "\(ControlItem.Identifier.visible.rawValue).Spacer.0"
        )

        XCTAssertTrue(tag.isControlItem)
    }

    func testIsSpacerTagRejectsDividerSpacersAndForeignItems() {
        let userSpacer = MenuBarItemTag(
            namespace: .thaw,
            title: "\(MenuBarSpacerManager.autosavePrefix)\(UUID().uuidString)"
        )
        let divider = MenuBarItemTag(
            namespace: .thaw,
            title: "\(ControlItem.Identifier.hidden.rawValue).Spacer.1"
        )
        let foreign = MenuBarItemTag(namespace: .systemUIServer, title: "Item-0")

        XCTAssertTrue(MenuBarSpacerManager.isSpacerTag(userSpacer))
        XCTAssertFalse(MenuBarSpacerManager.isSpacerTag(divider))
        XCTAssertFalse(MenuBarSpacerManager.isSpacerTag(foreign))
    }
}
