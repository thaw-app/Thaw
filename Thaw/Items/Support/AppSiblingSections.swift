//
//  AppSiblingSections.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Which items win when macOS hides an app as a whole.
nonisolated enum AppWideHidingRule: Equatable, Sendable {
    /// The Standard assertion conceals the whole app while any of its items is hidden.
    case hiddenWins
    /// Native hiding keeps the whole app on the bar while any of its items is visible.
    case visibleWins

    init(nativeAppHidingActive: Bool) {
        self = nativeAppHidingActive ? .visibleWins : .hiddenWins
    }
}

/// Where macOS puts an item of a split app, when that differs from its section in Layout.
nonisolated enum AppWideOverride: Equatable, Sendable {
    /// A Visible item that is not on the bar because an item of its app is in this concealed section.
    case hiddenWithApp(MenuBarSection.Name)
    /// An item of this concealed section that stays on the bar because an item of its app is Visible.
    case shownWithApp(MenuBarSection.Name)

    /// The concealed section the app's items can all move to instead of Visible.
    var concealedSection: MenuBarSection.Name {
        switch self {
        case let .hiddenWithApp(section), let .shownWithApp(section):
            section
        }
    }

    /// Whether the item is missing from the bar while Layout shows it as Visible.
    var isOffTheBar: Bool {
        if case .hiddenWithApp = self {
            return true
        }
        return false
    }

    /// Layout's tooltip for the item, saying where macOS puts it.
    func tooltip(itemName: String) -> String {
        switch self {
        case .hiddenWithApp:
            String(localized: "\(itemName) is not in the menu bar. macOS hides this app as a whole, and another of its items is hidden. Right-click to move them together.")
        case .shownWithApp:
            String(localized: "\(itemName) stays in the menu bar. macOS shows this app as a whole, and another of its items is in Visible. Right-click to move them together.")
        }
    }

    /// The note at the top of the item's menu in Layout.
    func menuNote(appName: String) -> String {
        switch self {
        case .hiddenWithApp:
            String(localized: "Hidden with \(appName)’s other items")
        case .shownWithApp:
            String(localized: "Shown with \(appName)’s other items")
        }
    }
}

/// Apps whose items are assigned to more than one section.
///
/// macOS 27 hides an app as a whole, so its items cannot be split across the
/// bar. The Standard assertion hides them all while any one is concealed, and
/// Native hiding shows them all while any one is visible. A split comes from
/// paths the automatic groups do not see: a later item arriving into the
/// new-items section, an ungrouped app moved piecemeal, a layout carried over
/// from macOS 26.
nonisolated enum AppSiblingSections {
    /// Where macOS puts item under rule, or nil when its section in Layout
    /// holds. Only apps that can be hidden count; system hosts carry many
    /// unrelated modules under one owner.
    static func appWideOverride(
        of item: MenuBarItem,
        among items: [MenuBarItem],
        rule: AppWideHidingRule,
        section: (MenuBarItem) -> MenuBarSection.Name
    ) -> AppWideOverride? {
        let ownSection = section(item)
        switch rule {
        case .hiddenWins:
            guard ownSection == .visible else { return nil }
            return concealingSiblingSection(of: item, among: items, section: section)
                .map(AppWideOverride.hiddenWithApp)
        case .visibleWins:
            guard ownSection != .visible,
                  siblingSections(of: item, among: items, section: section).contains(.visible)
            else { return nil }
            return .shownWithApp(ownSection)
        }
    }

    /// The concealed section another item of item's app is in, preferring
    /// Always Hidden. Only apps that can be hidden count; system hosts carry
    /// many unrelated modules under one owner.
    static func concealingSiblingSection(
        of item: MenuBarItem,
        among items: [MenuBarItem],
        section: (MenuBarItem) -> MenuBarSection.Name
    ) -> MenuBarSection.Name? {
        let sections = siblingSections(of: item, among: items, section: section)
        if sections.contains(.alwaysHidden) {
            return .alwaysHidden
        }
        if sections.contains(.hidden) {
            return .hidden
        }
        return nil
    }

    /// The section a newly arrived item's app already lives in, when all its
    /// other items agree on one.
    static func sectionOfAppSiblings(
        of item: MenuBarItem,
        among items: [MenuBarItem],
        section: (MenuBarItem) -> MenuBarSection.Name
    ) -> MenuBarSection.Name? {
        let sections = siblingSections(of: item, among: items, section: section)
        return sections.count == 1 ? sections.first : nil
    }

    /// The sections the other hideable items of item's app are in.
    private static func siblingSections(
        of item: MenuBarItem,
        among items: [MenuBarItem],
        section: (MenuBarItem) -> MenuBarSection.Name
    ) -> Set<MenuBarSection.Name> {
        guard MenuBarItemGrouping.isGroupable(item.tag) else { return [] }
        return Set(
            items
                .filter {
                    $0.tag.namespace == item.tag.namespace
                        && $0.uniqueIdentifier != item.uniqueIdentifier
                        && MenuBarItemGrouping.isGroupable($0.tag)
                }
                .map(section)
        )
    }
}
