//
//  SplitAppSectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// Pins the rules for apps whose items sit in more than one section. macOS 27
/// hides an app as a whole, so a concealed sibling hides the rest too.
struct SplitAppSectionTests {
    private func item(_ bundle: String, _ title: String, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0),
            windowID: CGWindowID(x),
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 3, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("a Visible item whose sibling is Hidden is pulled into Hidden")
    func hiddenSiblingConceals() {
        let shown = item("com.example.app", "A", x: 10)
        let hidden = item("com.example.app", "B", x: 40)
        let sections: [String: MenuBarSection.Name] = [shown.uniqueIdentifier: .visible, hidden.uniqueIdentifier: .hidden]
        let result = MenuBarItemManager.concealingSiblingSection(
            of: shown, among: [shown, hidden], section: { sections[$0.uniqueIdentifier] ?? .visible }
        )
        #expect(result == .hidden)
    }

    @Test("items of other apps never pull an item in")
    func otherAppsDoNotCount() {
        let shown = item("com.example.app", "A", x: 10)
        let other = item("com.example.other", "B", x: 40)
        let sections: [String: MenuBarSection.Name] = [shown.uniqueIdentifier: .visible, other.uniqueIdentifier: .hidden]
        #expect(MenuBarItemManager.concealingSiblingSection(
            of: shown, among: [shown, other], section: { sections[$0.uniqueIdentifier] ?? .visible }
        ) == nil)
    }

    @Test("a new item joins the section its app's other items agree on")
    func newItemJoinsSiblings() {
        let arriving = item("com.example.app", "New", x: 10)
        let a = item("com.example.app", "A", x: 40)
        let b = item("com.example.app", "B", x: 70)
        #expect(MenuBarItemManager.sectionOfAppSiblings(
            of: arriving, among: [arriving, a, b], section: { $0.uniqueIdentifier == arriving.uniqueIdentifier ? .hidden : .visible }
        ) == .visible)
    }

    @Test("siblings that already disagree give no answer")
    func splitSiblingsGiveNoAnswer() {
        let arriving = item("com.example.app", "New", x: 10)
        let a = item("com.example.app", "A", x: 40)
        let b = item("com.example.app", "B", x: 70)
        let sections: [String: MenuBarSection.Name] = [a.uniqueIdentifier: .visible, b.uniqueIdentifier: .hidden]
        #expect(MenuBarItemManager.sectionOfAppSiblings(
            of: arriving, among: [arriving, a, b], section: { sections[$0.uniqueIdentifier] ?? .hidden }
        ) == nil)
    }
}
