//
//  LayoutBarItemMenu.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// An `NSMenuItem` that runs a closure, so menu construction stays in one place
/// instead of being spread across target/action selectors on the views.
/// `nonisolated` because `NSMenuItem`'s initializers are, and an isolated
/// subclass cannot override them. Menu actions always fire on the main thread,
/// so the handler is `@MainActor` and `run` asserts that rather than hopping.
final nonisolated class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, isEnabled: Bool = true, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        // Copy the closure out first: passing `self` into the isolated region
        // would be sending a non-Sendable reference across the boundary.
        let handler = handler
        MainActor.assumeIsolated { handler() }
    }
}

/// Builds the layout bar's right-click menu.
///
/// Right-click is the group-editing surface because the bar's entire
/// interaction budget is already spent on drag: `LayoutBarItemView` overrides
/// `mouseDragged` and never handles `mouseDown`, so a selection mode would have
/// to thread itself through the drag gesture, add selection chrome competing
/// with the group chrome, and land in the file whose every comment documents a
/// past drag-state bug. Right-click costs one method and is the platform-native
/// "act on this object" gesture. The settings list is the discoverable and
/// keyboard-accessible counterpart.
@MainActor
enum LayoutBarItemMenu {
    enum Subject {
        case item(MenuBarItem)
        case group(ResolvedGroup)
    }

    /// Builds the menu, or returns `nil` when there is nothing to offer.
    ///
    /// Returns `nil` on the legacy backend: grouping is macOS 27-only, and there
    /// `sectionController` is nil so every edit would optional-chain into a
    /// no-op. Offering menu items that silently do nothing is worse than
    /// offering none.
    static func menu(
        subject: Subject,
        section: MenuBarSection.Name,
        orderedItems: [MenuBarItem],
        appState: AppState
    ) -> NSMenu? {
        guard !MenuBarBackendProvider.current.supportsLegacySectionHiding else {
            return nil
        }
        let manager = appState.itemGroupManager
        let groups = manager.resolvedGroups(for: orderedItems)
        let menu = NSMenu()

        switch subject {
        case let .item(item):
            if let group = groups.first(where: { group in
                group.memberIndices.contains { index in
                    orderedItems.indices.contains(index) && orderedItems[index].tag == item.tag
                }
            }) {
                addMemberEntries(
                    to: menu,
                    item: item,
                    group: group,
                    orderedItems: orderedItems,
                    manager: manager
                )
            } else {
                addNonMemberEntries(
                    to: menu,
                    item: item,
                    groups: groups,
                    orderedItems: orderedItems,
                    section: section,
                    manager: manager
                )
            }
        case let .group(group):
            addGroupEntries(to: menu, group: group, orderedItems: orderedItems, manager: manager)
        }

        return menu.items.isEmpty ? nil : menu
    }

    // MARK: Non-member

    private static func addNonMemberEntries(
        to menu: NSMenu,
        item: MenuBarItem,
        groups: [ResolvedGroup],
        orderedItems: [MenuBarItem],
        section _: MenuBarSection.Name,
        manager: MenuBarItemGroupManager
    ) {
        guard MenuBarItemGrouping.isGroupable(item.tag) else {
            menu.addItem(
                ClosureMenuItem(
                    title: String(localized: "“\(item.displayName)” can’t be grouped"),
                    isEnabled: false
                ) {}
            )
            return
        }

        // Pairing with another loose item is how a group gets created — a group
        // needs two members, so "New Group" on its own could not make one.
        let partners = orderedItems.filter { candidate in
            candidate.tag != item.tag
                && MenuBarItemGrouping.isGroupable(candidate.tag)
                && !groups.contains { group in
                    group.memberIndices.contains { index in
                        orderedItems.indices.contains(index) && orderedItems[index].tag == candidate.tag
                    }
                }
        }
        if !partners.isEmpty {
            let submenu = NSMenu()
            for partner in partners {
                submenu.addItem(
                    ClosureMenuItem(title: partner.displayName) {
                        manager.createGroup(name: nil, items: [item, partner])
                    }
                )
            }
            let entry = NSMenuItem(title: String(localized: "Group With"), action: nil, keyEquivalent: "")
            entry.submenu = submenu
            menu.addItem(entry)
        }

        if !groups.isEmpty {
            let submenu = NSMenu()
            for group in groups {
                let name = manager.displayName(for: group, in: orderedItems)
                submenu.addItem(
                    ClosureMenuItem(title: name) {
                        guard case let .user(id) = group.origin else {
                            // An automatic cluster has no stored record yet, so
                            // materialize it before adding a foreign member.
                            let members = group.memberIndices.compactMap {
                                orderedItems.indices.contains($0) ? orderedItems[$0] : nil
                            }
                            manager.createGroup(name: name, items: members + [item])
                            return
                        }
                        manager.add(item, to: id)
                    }
                )
            }
            let entry = NSMenuItem(title: String(localized: "Add to Group"), action: nil, keyEquivalent: "")
            entry.submenu = submenu
            menu.addItem(entry)
        }
    }

    // MARK: Member

    private static func addMemberEntries(
        to menu: NSMenu,
        item: MenuBarItem,
        group: ResolvedGroup,
        orderedItems: [MenuBarItem],
        manager: MenuBarItemGroupManager
    ) {
        addGroupEntries(to: menu, group: group, orderedItems: orderedItems, manager: manager)
        menu.addItem(.separator())
        menu.addItem(
            ClosureMenuItem(title: String(localized: "Remove “\(item.displayName)” from Group")) {
                manager.removeMember(item)
            }
        )
    }

    private static func addGroupEntries(
        to menu: NSMenu,
        group: ResolvedGroup,
        orderedItems: [MenuBarItem],
        manager: MenuBarItemGroupManager
    ) {
        let name = manager.displayName(for: group, in: orderedItems)
        let members = group.memberIndices.compactMap {
            orderedItems.indices.contains($0) ? orderedItems[$0] : nil
        }

        menu.addItem(
            ClosureMenuItem(
                title: group.isCollapsed
                    ? String(localized: "Expand “\(name)”")
                    : String(localized: "Collapse “\(name)”")
            ) {
                manager.setCollapsed(!group.isCollapsed, for: group.origin, members: members)
            }
        )
        menu.addItem(
            ClosureMenuItem(title: String(localized: "Ungroup “\(name)”")) {
                manager.ungroup(group.origin)
            }
        )
    }
}
