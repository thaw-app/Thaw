//
//  SavedIdentityAdoptionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// The provider's identity hook hands placeholder items their saved identity before any consumer sees them.
struct SavedIdentityAdoptionTests {
    private static let oneDrive = "com.microsoft.OneDrive"

    private static func item(title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(oneDrive), title: title, instanceIndex: 0),
            windowID: CGWindowID(x),
            ownerPID: 1130,
            sourcePID: 1130,
            bounds: CGRect(x: x, y: 3, width: 26, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A bare OneDrive item leaves the walk under its saved account identity")
    func placeholderLeavesUnderSavedIdentity() {
        let bare = Self.item(title: "OneDrive", x: 2188)
        let items = MenuBarItemAXProvider.adoptingSavedIdentities([bare]) {
            ["hidden": ["\(Self.oneDrive):Daniel Scherber"]]
        }
        #expect(items.map(\.uniqueIdentifier) == ["\(Self.oneDrive):Daniel Scherber"])
        #expect(items[0].windowID == bare.windowID)
    }

    @Test("The saved order is not read when no item answered under a placeholder name")
    func savedOrderIsReadOnlyForPlaceholders() {
        let named = Self.item(title: "OneDrive — Personal", x: 2188)
        var reads = 0
        let items = MenuBarItemAXProvider.adoptingSavedIdentities([named]) {
            reads += 1
            return [:]
        }
        #expect(items == [named])
        #expect(reads == 0)
    }

    @Test("A placeholder with nothing saved for it keeps its name")
    func placeholderWithoutSavedTitleIsUnchanged() {
        let bare = Self.item(title: "OneDrive", x: 2188)
        let items = MenuBarItemAXProvider.adoptingSavedIdentities([bare]) { [:] }
        #expect(items == [bare])
    }
}
