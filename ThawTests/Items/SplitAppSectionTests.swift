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
/// hides an app as a whole: under the Standard assertion a concealed sibling
/// hides the rest too, and under Native hiding a visible sibling shows them.
@MainActor
struct SplitAppSectionTests {
    private func item(_ bundle: String, _ title: String, x: CGFloat) -> MenuBarItem {
        item(MenuBarItemTag(namespace: .string(bundle), title: title, instanceIndex: 0), x: x)
    }

    private func item(_ tag: MenuBarItemTag, x: CGFloat) -> MenuBarItem {
        MenuBarItem(
            tag: tag,
            windowID: CGWindowID(x),
            ownerPID: 100,
            sourcePID: 200,
            bounds: CGRect(x: x, y: 3, width: 24, height: 24),
            title: tag.title,
            isOnScreen: true
        )
    }

    @Test("a Visible item whose sibling is Hidden is pulled into Hidden")
    func hiddenSiblingConceals() {
        let shown = item("com.example.app", "A", x: 10)
        let hidden = item("com.example.app", "B", x: 40)
        let sections: [String: MenuBarSection.Name] = [shown.uniqueIdentifier: .visible, hidden.uniqueIdentifier: .hidden]
        let result = AppSiblingSections.concealingSiblingSection(
            of: shown, among: [shown, hidden], section: { sections[$0.uniqueIdentifier] ?? .visible }
        )
        #expect(result == .hidden)
    }

    @Test("items of other apps never pull an item in")
    func otherAppsDoNotCount() {
        let shown = item("com.example.app", "A", x: 10)
        let other = item("com.example.other", "B", x: 40)
        let sections: [String: MenuBarSection.Name] = [shown.uniqueIdentifier: .visible, other.uniqueIdentifier: .hidden]
        #expect(AppSiblingSections.concealingSiblingSection(
            of: shown, among: [shown, other], section: { sections[$0.uniqueIdentifier] ?? .visible }
        ) == nil)
    }

    @Test("a new item joins the section its app's other items agree on")
    func newItemJoinsSiblings() {
        let arriving = item("com.example.app", "New", x: 10)
        let a = item("com.example.app", "A", x: 40)
        let b = item("com.example.app", "B", x: 70)
        #expect(AppSiblingSections.sectionOfAppSiblings(
            of: arriving, among: [arriving, a, b], section: { $0.uniqueIdentifier == arriving.uniqueIdentifier ? .hidden : .visible }
        ) == .visible)
    }

    @Test("siblings that already disagree give no answer")
    func splitSiblingsGiveNoAnswer() {
        let arriving = item("com.example.app", "New", x: 10)
        let a = item("com.example.app", "A", x: 40)
        let b = item("com.example.app", "B", x: 70)
        let sections: [String: MenuBarSection.Name] = [a.uniqueIdentifier: .visible, b.uniqueIdentifier: .hidden]
        #expect(AppSiblingSections.sectionOfAppSiblings(
            of: arriving, among: [arriving, a, b], section: { sections[$0.uniqueIdentifier] ?? .hidden }
        ) == nil)
    }

    // MARK: Which items win

    private nonisolated static let sectionsUnderTest: [MenuBarSection.Name] = [.visible, .hidden, .alwaysHidden]

    @Test(
        "each hiding rule flags the item its app overrides, and only that one",
        arguments: [AppWideHidingRule.hiddenWins, .visibleWins],
        sectionsUnderTest.flatMap { own in sectionsUnderTest.map { (own, $0) } }
    )
    func ruleDecidesOverride(rule: AppWideHidingRule, sections: (own: MenuBarSection.Name, sibling: MenuBarSection.Name)) {
        let subject = item("com.example.app", "A", x: 10)
        let sibling = item("com.example.app", "B", x: 40)
        let assigned = [subject.uniqueIdentifier: sections.own, sibling.uniqueIdentifier: sections.sibling]
        let result = AppSiblingSections.appWideOverride(
            of: subject, among: [subject, sibling], rule: rule, section: { assigned[$0.uniqueIdentifier] ?? .visible }
        )
        let expected: AppWideOverride? = switch rule {
        case .hiddenWins:
            sections.own == .visible && sections.sibling != .visible ? .hiddenWithApp(sections.sibling) : nil
        case .visibleWins:
            sections.own != .visible && sections.sibling == .visible ? .shownWithApp(sections.own) : nil
        }
        #expect(result == expected)
    }

    @Test("an app with no other items is never overridden", arguments: [AppWideHidingRule.hiddenWins, .visibleWins], sectionsUnderTest)
    func loneItemKeepsItsSection(rule: AppWideHidingRule, own: MenuBarSection.Name) {
        let subject = item("com.example.app", "A", x: 10)
        let other = item("com.example.other", "B", x: 40)
        let flipped: MenuBarSection.Name = own == .visible ? .hidden : .visible
        let result = AppSiblingSections.appWideOverride(
            of: subject,
            among: [subject, other],
            rule: rule,
            section: { $0.uniqueIdentifier == subject.uniqueIdentifier ? own : flipped }
        )
        #expect(result == nil)
    }

    @Test("under the Standard assertion Always Hidden wins over Hidden")
    func standardPrefersAlwaysHidden() {
        let shown = item("com.example.app", "A", x: 10)
        let hidden = item("com.example.app", "B", x: 40)
        let buried = item("com.example.app", "C", x: 70)
        let assigned: [String: MenuBarSection.Name] = [
            shown.uniqueIdentifier: .visible, hidden.uniqueIdentifier: .hidden, buried.uniqueIdentifier: .alwaysHidden,
        ]
        let result = AppSiblingSections.appWideOverride(
            of: shown, among: [shown, hidden, buried], rule: .hiddenWins, section: { assigned[$0.uniqueIdentifier] ?? .visible }
        )
        #expect(result == .hiddenWithApp(.alwaysHidden))
        #expect(result?.isOffTheBar == true)
        #expect(result?.concealedSection == .alwaysHidden)
    }

    @Test("under Native hiding an item shown with its app offers its own section as the concealed one")
    func nativeOffersOwnSection() {
        let buried = item("com.example.app", "A", x: 10)
        let shown = item("com.example.app", "B", x: 40)
        let assigned: [String: MenuBarSection.Name] = [buried.uniqueIdentifier: .alwaysHidden, shown.uniqueIdentifier: .visible]
        let result = AppSiblingSections.appWideOverride(
            of: buried, among: [buried, shown], rule: .visibleWins, section: { assigned[$0.uniqueIdentifier] ?? .visible }
        )
        #expect(result == .shownWithApp(.alwaysHidden))
        #expect(result?.isOffTheBar == false)
        #expect(result?.concealedSection == .alwaysHidden)
    }

    @Test("the rule follows whether Native hiding is running", arguments: [(true, AppWideHidingRule.visibleWins), (false, .hiddenWins)])
    func ruleFollowsNativeState(active: Bool, expected: AppWideHidingRule) {
        #expect(AppWideHidingRule(nativeAppHidingActive: active) == expected)
    }

    @Test("the tooltip and menu note say which way macOS settled the app", arguments: [
        (AppWideOverride.hiddenWithApp(.hidden), "is not in the menu bar", "Hidden with"),
        (.shownWithApp(.alwaysHidden), "stays in the menu bar", "Shown with"),
    ])
    func wordingFollowsOverride(override: AppWideOverride, tooltipPhrase: String, notePrefix: String) {
        let tooltip = override.tooltip(itemName: "Dropbox")
        #expect(tooltip.hasPrefix("Dropbox \(tooltipPhrase)."))
        #expect(override.menuNote(appName: "Dropbox") == "\(notePrefix) Dropbox’s other items")
    }

    // MARK: Folders take whole apps

    @Test("a folder takes the other items of its members' apps, after the members and in bar order (#1617)")
    func folderTakesAppSiblings() {
        let raycast = item("com.raycast.macos", "Raycast", x: 10)
        let other = item("com.example.other", "Other", x: 40)
        let command = item("com.raycast.macos", "Command", x: 70)
        let unrelated = item("com.example.unrelated", "Unrelated", x: 100)
        let quicklink = item("com.raycast.macos", "Quicklink", x: 130)
        let batch = AppSiblingSections.withAppSiblings(
            [other, raycast],
            among: [raycast, other, command, unrelated, quicklink]
        )
        #expect(batch.map(\.uniqueIdentifier) == [other, raycast, command, quicklink].map(\.uniqueIdentifier))
    }

    @Test("members whose apps have no other items come back unchanged")
    func folderWithoutSiblings() {
        let a = item("com.example.a", "A", x: 10)
        let b = item("com.example.b", "B", x: 40)
        let c = item("com.example.c", "C", x: 70)
        let batch = AppSiblingSections.withAppSiblings([b, a], among: [a, b, c])
        #expect(batch.map(\.uniqueIdentifier) == [b, a].map(\.uniqueIdentifier))
    }

    @Test("items that can't be hidden on their own neither bring siblings nor join as one")
    func folderSkipsUnhideableItems() {
        let wifi = item(MenuBarItemTag(namespace: .menuBarAgent, title: "WiFi"), x: 10)
        let battery = item(MenuBarItemTag(namespace: .menuBarAgent, title: "Battery"), x: 40)
        let control = item(.visibleControlItem, x: 70)
        let app = item("com.example.app", "A", x: 100)
        let batch = AppSiblingSections.withAppSiblings([wifi, app], among: [wifi, battery, control, app])
        #expect(batch.map(\.uniqueIdentifier) == [wifi, app].map(\.uniqueIdentifier))
    }
}
