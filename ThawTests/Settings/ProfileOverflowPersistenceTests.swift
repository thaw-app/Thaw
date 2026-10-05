//
//  ProfileOverflowPersistenceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// A profile captured while the bar is tight must not record an
/// authored-Visible item as Hidden. Profile capture shares
/// MenuBarItemManager.computeSectionOrder, so the overflow projection is the
/// only thing that keeps the saved slot alive.
@MainActor
@Suite("Profile overflow persistence")
struct ProfileOverflowPersistenceTests {
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

    /// A profile manager whose profiles live in a throwaway directory, so the
    /// test never reads or rewrites the tester's real profiles.
    private func withManager<T>(_ body: (ProfileManager) throws -> T) throws -> T {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfileOverflowPersistenceTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try body(ProfileManager(profilesDirectory: tmp))
    }

    @Test("Profile capture keeps an overflowed Visible item in Visible")
    func captureKeepsOverflowedItemVisible() throws {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        manager.authoredLayoutSourceOverride = MenuBarItemManager.AuthoredLayoutSource(
            sectionAssignment: [:],
            sectionItemOrder: [.visible: [a, b, c].map(\.uniqueIdentifier)]
        )

        try withManager { profileManager in
            let snapshot = profileManager.captureCurrentLayout(from: manager, groups: .empty)

            #expect(snapshot.itemOrder?[MenuBarSectionName.visible.rawValue] == [a, b, c].map(\.uniqueIdentifier))
            #expect(snapshot.savedSectionOrder[MenuBarSectionName.visible.rawValue] == [a, b, c].map(\.uniqueIdentifier))
            #expect(snapshot.itemSectionMap?[b.uniqueIdentifier] == MenuBarSectionName.visible.rawValue)
            #expect(snapshot.itemSectionMap?[a.uniqueIdentifier] == MenuBarSectionName.visible.rawValue)
            #expect(snapshot.itemSectionMap?[c.uniqueIdentifier] == MenuBarSectionName.visible.rawValue)
        }
    }

    @Test("Profile capture after overflow clears still keeps the item Visible")
    func captureAfterOverflowClearKeepsItemVisible() throws {
        // The controller cleared overflow but the cache still shows B Hidden.
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        manager.authoredLayoutSourceOverride = MenuBarItemManager.AuthoredLayoutSource(
            sectionAssignment: [:],
            sectionItemOrder: [.visible: [a, b, c].map(\.uniqueIdentifier)]
        )

        try withManager { profileManager in
            let snapshot = profileManager.captureCurrentLayout(from: manager, groups: .empty)

            #expect(snapshot.itemOrder?[MenuBarSectionName.visible.rawValue] == [a, b, c].map(\.uniqueIdentifier))
            #expect(snapshot.itemSectionMap?[b.uniqueIdentifier] == MenuBarSectionName.visible.rawValue)
        }
    }

    @Test("Profile capture keeps an authored-Hidden item Hidden")
    func captureKeepsAuthoredHiddenItemHidden() throws {
        let a = Self.item("A", x: 10)
        let b = Self.item("B", x: 40)
        let c = Self.item("C", x: 70)
        let manager = MenuBarItemManager()
        manager.itemCache[.visible] = [a, c]
        manager.itemCache[.hidden] = [b]
        manager.authoredLayoutSourceOverride = MenuBarItemManager.AuthoredLayoutSource(
            sectionAssignment: [b.uniqueIdentifier: .hidden],
            sectionItemOrder: [.visible: [a, c].map(\.uniqueIdentifier), .hidden: [b.uniqueIdentifier]]
        )

        try withManager { profileManager in
            let snapshot = profileManager.captureCurrentLayout(from: manager, groups: .empty)

            #expect(snapshot.itemOrder?[MenuBarSectionName.visible.rawValue] == [a, c].map(\.uniqueIdentifier))
            #expect(snapshot.itemOrder?[MenuBarSectionName.hidden.rawValue] == [b.uniqueIdentifier])
            #expect(snapshot.itemSectionMap?[b.uniqueIdentifier] == MenuBarSectionName.hidden.rawValue)
        }
    }
}
