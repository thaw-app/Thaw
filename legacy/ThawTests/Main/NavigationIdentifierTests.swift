//
//  NavigationIdentifierTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Navigation identifier labels")
struct NavigationIdentifierTests {
    /// `SettingsNavigationIdentifier` overrides `localized`, so the protocol default
    /// is only reachable through a conformer that doesn't.
    @Test("A String-raw conformer labels itself with its raw value")
    func defaultLocalizedUsesTheRawValue() {
        #expect(PlainNavigationIdentifier.first.localized == LocalizedStringKey("First Destination"))
        #expect(PlainNavigationIdentifier.second.localized == LocalizedStringKey("Second Destination"))
    }

    @Test("The shipping conformer overrides the default rather than inheriting it")
    func settingsIdentifierOverridesTheDefault() {
        // `menuBarLayout`'s raw value is its persisted name; its label is
        // the short sidebar title. Dropping the override would make the
        // sidebar read "Menu Bar Layout".
        #expect(SettingsNavigationIdentifier.menuBarLayout.rawValue == "Menu Bar Layout")
        #expect(SettingsNavigationIdentifier.menuBarLayout.localized == LocalizedStringKey("Layout"))
    }
}

/// Does not override `localized`, so the protocol's `RawValue == String` default runs.
private enum PlainNavigationIdentifier: String, NavigationIdentifier {
    typealias ID = Int

    case first = "First Destination"
    case second = "Second Destination"

    var iconResource: IconResource {
        .systemSymbol("gearshape")
    }
}
