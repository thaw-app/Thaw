//
//  NewItemRouteTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A new item reaches the section the New Items setting names")
struct NewItemRouteTests {
    /// A newcomer bound for a concealed section's divider is assigned the section; one with an
    /// anchor item to sit beside, or bound for Visible, which it is in already, is moved.
    @Test(
        "A newcomer is assigned only to a concealed section's divider",
        arguments: [
            (MenuBarSectionName.hidden, true, NewItemRoute.assign),
            (.alwaysHidden, true, .assign),
            (.visible, true, .move),
            (.hidden, false, .move),
            (.visible, false, .move),
        ]
    )
    func route(section: MenuBarSectionName, destinationIsDivider: Bool, expected: NewItemRoute) {
        #expect(NewItemRoute(section: section, destinationIsDivider: destinationIsDivider) == expected)
    }
}
