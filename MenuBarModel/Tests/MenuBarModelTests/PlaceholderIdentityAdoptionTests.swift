//
//  PlaceholderIdentityAdoptionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import MenuBarModel
import Testing

/// OneDrive answers as "OneDrive" or unnamed until the account loads; the saved account titles
/// stand in for the placeholders by place on the bar.
@Suite("Placeholder identity adoption")
struct PlaceholderIdentityAdoptionTests {
    private static let oneDrive = "com.microsoft.OneDrive"

    private static func item(_ bundleID: String, title: String, x: CGFloat, pid: pid_t = 1130) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundleID), title: title, instanceIndex: 0),
            windowID: CGWindowID(x),
            ownerPID: pid,
            sourcePID: pid,
            bounds: CGRect(x: x, y: 3, width: 26, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    private static func identifiers(_ items: [MenuBarItem]) -> [String] {
        items.map(\.uniqueIdentifier)
    }

    // MARK: Saved titles

    @Test("Saved titles come in bar order and leave out placeholders, instances and other apps")
    func savedTitlesInBarOrder() {
        let order = [
            "visible": ["\(Self.oneDrive):OneDrive — Personal", "com.example.app:Item-0"],
            "hidden": ["\(Self.oneDrive):OneDrive — Work", "\(Self.oneDrive):OneDrive", "\(Self.oneDrive):OneDrive — Work:1"],
            "alwaysHidden": ["\(Self.oneDrive):Item-0", "\(Self.oneDrive):Daniel Scherber"],
        ]
        #expect(PlaceholderIdentityAdoption.savedTitles(in: order) == [
            Self.oneDrive: ["Daniel Scherber", "OneDrive — Work", "OneDrive — Personal"],
        ])
    }

    @Test("A saved title is handed out once")
    func savedTitlesAreUnique() {
        let order = [
            "hidden": ["\(Self.oneDrive):OneDrive — Work"],
            "visible": ["\(Self.oneDrive):OneDrive — Work"],
        ]
        #expect(PlaceholderIdentityAdoption.savedTitles(in: order) == [Self.oneDrive: ["OneDrive — Work"]])
    }

    // MARK: Adoption

    @Test("A bare OneDrive item takes the one saved account title and keeps its window and frame")
    func barePlaceholderTakesSavedTitle() {
        let bare = Self.item(Self.oneDrive, title: "OneDrive", x: 2188)
        let result = PlaceholderIdentityAdoption.adopting([bare], savedTitles: [Self.oneDrive: ["Daniel Scherber"]])
        let adopted = result.items[0]
        #expect(adopted.uniqueIdentifier == "\(Self.oneDrive):Daniel Scherber")
        #expect(adopted.windowID == bare.windowID)
        #expect(adopted.bounds == bare.bounds)
        #expect(adopted.title == "OneDrive")
        #expect(adopted.sourcePID == bare.sourcePID)
        #expect(result.adopted == ["\(Self.oneDrive):OneDrive": "\(Self.oneDrive):Daniel Scherber"])
    }

    @Test("Two placeholders take the saved titles left to right, whatever order the items came in")
    func placeholdersTakeTitlesByPlace() {
        let right = Self.item(Self.oneDrive, title: "OneDrive", x: 2200)
        let left = Self.item(Self.oneDrive, title: "Item-1", x: 1900)
        let result = PlaceholderIdentityAdoption.adopting(
            [right, left],
            savedTitles: [Self.oneDrive: ["OneDrive — Work", "OneDrive — Personal"]]
        )
        #expect(Self.identifiers(result.items) == [
            "\(Self.oneDrive):OneDrive — Personal",
            "\(Self.oneDrive):OneDrive — Work",
        ])
    }

    @Test("A title the app already answered with is not handed out again")
    func answeredTitleIsNotHandedOut() {
        let personal = Self.item(Self.oneDrive, title: "OneDrive — Personal", x: 2200)
        let bare = Self.item(Self.oneDrive, title: "OneDrive", x: 1900)
        let result = PlaceholderIdentityAdoption.adopting(
            [personal, bare],
            savedTitles: [Self.oneDrive: ["OneDrive — Personal", "OneDrive — Work"]]
        )
        #expect(Self.identifiers(result.items) == [
            "\(Self.oneDrive):OneDrive — Personal",
            "\(Self.oneDrive):OneDrive — Work",
        ])
    }

    @Test("A placeholder beyond the saved titles keeps its name")
    func extraPlaceholderStaysNew() {
        let first = Self.item(Self.oneDrive, title: "OneDrive", x: 1900)
        let second = Self.item(Self.oneDrive, title: "OneDrive", x: 2000)
        let result = PlaceholderIdentityAdoption.adopting([first, second], savedTitles: [Self.oneDrive: ["Daniel Scherber"]])
        #expect(Self.identifiers(result.items) == ["\(Self.oneDrive):Daniel Scherber", "\(Self.oneDrive):OneDrive"])
        #expect(result.adopted.count == 1)
    }

    @Test("Another app's unnamed item and an app with no saved titles are left alone")
    func otherItemsAreUntouched() {
        let other = Self.item("com.example.app", title: "Item-0", x: 1800, pid: 77)
        let bare = Self.item(Self.oneDrive, title: "OneDrive", x: 1900)
        let noSaved = PlaceholderIdentityAdoption.adopting([other, bare], savedTitles: [:])
        #expect(noSaved.items == [other, bare])
        #expect(noSaved.adopted.isEmpty)
        let otherApp = PlaceholderIdentityAdoption.adopting([other, bare], savedTitles: ["com.example.app": ["Named"]])
        #expect(otherApp.items == [other, bare])
    }

    @Test("Only a multiline-status app's bare name or an Item-N counts as a placeholder")
    func placeholderTitles() {
        #expect(PlaceholderIdentityAdoption.isPlaceholderTitle("OneDrive", bundleID: Self.oneDrive))
        #expect(PlaceholderIdentityAdoption.isPlaceholderTitle("Item-2", bundleID: Self.oneDrive))
        #expect(!PlaceholderIdentityAdoption.isPlaceholderTitle("OneDrive — Personal", bundleID: Self.oneDrive))
        #expect(!PlaceholderIdentityAdoption.isPlaceholderTitle("OneDrive", bundleID: "com.example.app"))
        #expect(PlaceholderIdentityAdoption.hasPlaceholderIdentity(Self.item(Self.oneDrive, title: "OneDrive", x: 1)))
        #expect(!PlaceholderIdentityAdoption.hasPlaceholderIdentity(Self.item("com.example.app", title: "Item-0", x: 1)))
    }
}
