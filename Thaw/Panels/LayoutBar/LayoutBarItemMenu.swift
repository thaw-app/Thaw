//
//  LayoutBarItemMenu.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Closure actions keep menu construction together; nonisolated permits overriding NSMenuItem initializers.
/// Actions run on the main thread, so run asserts MainActor isolation rather than hopping.
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
        // Copy the closure to avoid sending non-Sendable self into the isolated region.
        let handler = handler
        MainActor.assumeIsolated { handler() }
    }
}

/// Actions live here, properties in LayoutBarItemInspector; alert-reveal state is shared for direct right-click access.
/// Item views use mouse input for dragging, so groups use right-click; the settings list provides keyboard access.
@MainActor
enum LayoutBarItemMenu {
    enum Subject {
        case item(MenuBarItem)
        case group(ResolvedGroup)
    }

    /// Builds the menu, or returns nil when there is nothing to offer.
    static func menu(
        subject: Subject,
        section: MenuBarSection.Name,
        orderedItems: [MenuBarItem],
        appState: AppState,
        onRename: (@MainActor () -> Void)? = nil
    ) -> NSMenu? {
        let manager = appState.itemGroupManager
        let groups = manager.resolvedGroups(for: orderedItems)
        let menu = NSMenu()

        // Keep item actions first across surfaces for consistent discovery.
        if case let .item(item) = subject, !item.isControlItem {
            addItemEntries(to: menu, item: item, appState: appState, onRename: onRename)
            menu.addItem(.separator())
        }

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
                    manager: manager,
                    folders: appState.groupFolders
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
            addGroupEntries(
                to: menu,
                group: group,
                orderedItems: orderedItems,
                manager: manager,
                folders: appState.groupFolders
            )
        }

        if case let .item(item) = subject {
            addAlertRevealEntry(to: menu, item: item)
        }

        return menu.items.isEmpty ? nil : menu
    }

    /// Per-item temporary reveal is available on the same backend as this menu.
    private static func addAlertRevealEntry(to menu: NSMenu, item: MenuBarItem) {
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let identifier = item.tag.tagIdentifier
        let isEnabled = MenuBarItemAlertReveals.contains(identifier)
        let entry = ClosureMenuItem(title: String(localized: "Reveal When Its Icon Changes")) {
            MenuBarItemAlertReveals.setEnabled(!isEnabled, for: identifier)
        }
        entry.state = isEnabled ? .on : .off
        menu.addItem(entry)
    }

    private static func addItemEntries(
        to menu: NSMenu,
        item: MenuBarItem,
        appState: AppState,
        onRename: (@MainActor () -> Void)?
    ) {
        if let onRename {
            menu.addItem(ClosureMenuItem(title: String(localized: "Rename…"), handler: onRename))
        }
        if let hidingSection = appState.itemManager.sectionHidingItemWithItsApp(item, appState: appState) {
            addSplitAppEntries(to: menu, item: item, hidingSection: hidingSection, appState: appState)
        }
        menu.addItem(moveEntry(for: item, appState: appState))
        if appState.itemManager.isThawBarOnly(item) {
            let proxies = appState.thawBarOnlyProxies
            let isShown = proxies.isEnabled(for: item)
            let entry = ClosureMenuItem(title: String(localized: "Show in Menu Bar")) {
                proxies.setEnabled(!isShown, for: item)
            }
            entry.state = isShown ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(
            ClosureMenuItem(title: String(localized: "Choose Icon…")) {
                ItemIconPicker.present(for: item, appState: appState)
            }
        )
        menu.addItem(
            ClosureMenuItem(title: String(localized: "Set Shortcut…")) {
                SettingsSearchNavigation.selectSidebarPane(.hotkeys, navigationState: appState.navigationState)
                appState.prepareSettingsPresentation()
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
            }
        )
    }

    /// Explain app-wide hiding of Visible items and offer to move all siblings together.
    private static func addSplitAppEntries(
        to menu: NSMenu,
        item: MenuBarItem,
        hidingSection: MenuBarSection.Name,
        appState: AppState
    ) {
        let appName = item.sourceApplication?.localizedName ?? item.displayName
        let note = ClosureMenuItem(
            title: String(localized: "Hidden with \(appName)’s other items"),
            isEnabled: false
        ) {}
        menu.addItem(note)
        let members = appState.itemManager.appItems(for: item)
        for destination in [MenuBarSection.Name.visible, hidingSection] {
            let title = String(
                localized: "Move All \(appName) Items to \(MenuBarSearchItemActions.title(for: destination))"
            )
            menu.addItem(
                ClosureMenuItem(title: title) {
                    MenuBarSearchItemActions.move(members, to: destination, appState: appState)
                }
            )
        }
        menu.addItem(.separator())
    }

    /// Thaw Bar Only is app state, but appears alongside section destinations here.
    static func moveEntry(for item: MenuBarItem, appState: AppState) -> NSMenuItem {
        let itemManager = appState.itemManager
        let isThawBarOnly = itemManager.isThawBarOnly(item)
        let current = appState.menuBarManager.sectionController.section(for: item)
        let submenu = NSMenu()

        for (index, name) in MenuBarSearchItemActions.moveDestinations(appState: appState).enumerated() {
            guard let name else { continue }
            let entry = ClosureMenuItem(title: MenuBarSearchItemActions.title(for: name)) {
                if itemManager.isThawBarOnly(item) {
                    itemManager.returnFromThawBarOnly(item, to: name, appState: appState)
                } else {
                    MenuBarSearchItemActions.move(item, to: name, appState: appState)
                }
            }
            entry.state = !isThawBarOnly && name == current ? .on : .off
            entry.keyEquivalent = String(index + 1)
            entry.keyEquivalentModifierMask = .command
            submenu.addItem(entry)
        }
        if itemManager.isThawBarOnlyEnabled {
            let thawBarOnly = ClosureMenuItem(title: String(localized: "Thaw Bar Only")) {
                itemManager.moveToThawBarOnly(item, appState: appState)
            }
            thawBarOnly.state = isThawBarOnly ? .on : .off
            submenu.addItem(thawBarOnly)
        }

        let entry = NSMenuItem(title: String(localized: "Move to"), action: nil, keyEquivalent: "")
        entry.submenu = submenu
        return entry
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

        // Groups require two members, so creation must offer another loose item.
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
                            // Automatic clusters need a stored record before adding a foreign member.
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
        manager: MenuBarItemGroupManager,
        folders: GroupFolders
    ) {
        addGroupEntries(to: menu, group: group, orderedItems: orderedItems, manager: manager, folders: folders)
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
        manager: MenuBarItemGroupManager,
        folders: GroupFolders
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
        let isFolder = folders.isFolder(group.origin)
        menu.addItem(
            ClosureMenuItem(
                title: isFolder
                    ? String(localized: "Stop Showing “\(name)” as a Folder")
                    : String(localized: "Show “\(name)” as a Folder")
            ) {
                folders.setFolder(!isFolder, for: group.origin, members: members)
            }
        )
        menu.addItem(
            ClosureMenuItem(title: String(localized: "Ungroup “\(name)”")) {
                manager.ungroup(group.origin)
            }
        )
    }
}
