//
//  HotkeysSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct HotkeysSettingsPane: View {
    @Environment(AppState.self) var appState
    let settings: HotkeysSettings

    var body: some View {
        // Read here, not inside the alert's binding, so the pane observes it.
        let persistenceError = settings.lastPersistenceError

        ThawForm {
            ThawSection("Menu bar sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
                hotkeyRecorder(forAction: .toggleSwap)
            }
            ThawSection("Menu bar items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
                // Thaw Bar Only is unplugged for now.
                // hotkeyRecorder(forAction: .showThawBarOnlyItems)
                hotkeyRecorder(forAction: .showItemHints)
                MenuBarItemHotkeyList(
                    menuBarManager: appState.menuBarManager,
                    itemManager: appState.itemManager,
                    imageCache: appState.imageCache
                )
            }
            if !appState.profileManager.profiles.isEmpty {
                ThawSection("Profiles") {
                    ForEach(appState.profileManager.profiles) { meta in
                        profileHotkeyRecorder(for: meta)
                    }
                }
            }
            ThawSection("Other") {
                hotkeyRecorder(forAction: .revealSystemMenuBar)
                hotkeyRecorder(forAction: .enableThawBar)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
                hotkeyRecorder(forAction: .toggleAutoRehide)
                hotkeyRecorder(forAction: .toggleZenMode)
                hotkeyRecorder(forAction: .toggleLayoutEditor)
            }
        }
        // The shortcut is written from a change callback that cannot throw, so
        // a failed write reaches the user here rather than only the log.
        .alert(
            "Couldn’t save shortcut",
            item: Binding(
                get: { persistenceError },
                set: { _ in settings.clearPersistenceError() }
            )
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text("Toggle the Hidden section")
                case .toggleAlwaysHiddenSection:
                    Text("Toggle the Always Hidden section")
                case .toggleSwap:
                    Text("Swap shown and hidden items")
                case .searchMenuBarItems:
                    Text("Search menu bar items")
                case .showThawBarOnlyItems:
                    Text("Show Thaw Bar Only items")
                case .showItemHints:
                    Text("Open an item by letter")
                case .revealSystemMenuBar:
                    Text("Reveal the menu bar")
                case .enableThawBar:
                    Text("Turn \(Constants.displayName) Bar on or off")
                case .toggleApplicationMenus:
                    Text("Toggle application menus")
                case .toggleAutoRehide:
                    Text("Toggle automatic rehiding")
                case .toggleZenMode:
                    Text("Toggle Zen Mode")
                case .toggleLayoutEditor:
                    Text("Show Layout")
                case .profileApply:
                    EmptyView()
                case .openMenuBarItem:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func profileHotkeyRecorder(for meta: ProfileMetadata) -> some View {
        if let hotkey = appState.profileManager.profileHotkeys[meta.id] {
            HotkeyRecorder(hotkey: hotkey) {
                Text(meta.name)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forSection name: MenuBarSection.Name) -> some View {
        if appState.menuBarManager.section(withName: name)?.isEnabled == true {
            if case .hidden = name {
                hotkeyRecorder(forAction: .toggleHiddenSection)
            } else if case .alwaysHidden = name {
                hotkeyRecorder(forAction: .toggleAlwaysHiddenSection)
            }
        }
    }
}

// MARK: - MenuBarItemHotkeyList

/// Per-item hotkeys that open an item's menu. Bindings for apps that are not
/// running stay listed so they can be cleared.
private struct MenuBarItemHotkeyList: View {
    let menuBarManager: MenuBarManager
    let itemManager: MenuBarItemManager
    let imageCache: MenuBarItemImageCache

    @State private var isExpanded = false
    @State private var rows: [Row] = []

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if rows.isEmpty {
                Text("No menu bar items available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    ForEach(rows, id: \.id) { row in
                        GridRow {
                            iconView(for: row)
                                .gridColumnAlignment(.center)
                            Text(row.name)
                                .lineLimit(1)
                                // Keep the spacer column from truncating it.
                                .fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(row.item != nil ? .primary : .secondary)
                            Text(row.bundle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            // Absorbs the slack, pushing the recorder to the trailing edge.
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: 1)
                            HotkeyRecorder(hotkey: row.hotkey) {
                                EmptyView()
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
        } label: {
            Text("Open menu bar items")
        }
        // The image cache runs live capture only while the list is expanded.
        .onChange(of: isExpanded, initial: true) { _, expanded in
            imageCache.isItemHotkeyListExpanded = expanded
            rebuildRows()
        }
        .onChange(of: itemManager.itemCache) { rebuildRows() }
        .onChange(of: menuBarManager.itemHotkeys) { rebuildRows() }
        .onDisappear {
            imageCache.isItemHotkeyListExpanded = false
        }
        .task(id: isExpanded) {
            // Hidden sections are captured only on request, so prewarm them.
            guard isExpanded else { return }
            await imageCache.recaptureNow(sections: MenuBarSection.Name.allCases)
        }
    }

    @ViewBuilder
    private func iconView(for row: Row) -> some View {
        if let capture = row.item.flatMap({ imageCache.capturesByTag[$0.tag] }) {
            // Captured size, not a square that would distort wide items.
            Image(decorative: capture.cgImage, scale: capture.scale)
        } else {
            // Absent items have no capture.
            Image(systemName: "questionmark.square.dashed")
                .resizable()
                .scaledToFit()
                .frame(height: 18)
                .foregroundStyle(.secondary)
        }
    }

    private struct Row {
        let id: String
        let name: String
        let bundle: String
        let item: MenuBarItem?
        let hotkey: Hotkey
    }

    private func makeRows() -> [Row] {
        var rows: [Row] = []
        var seen = Set<String>()

        // By section, reversed so the rightmost item (the clock) comes first.
        for section in MenuBarSection.Name.allCases {
            for item in itemManager.managedItems(for: section).reversed()
                where !item.isControlItem && item.sourcePID != nil
            {
                let id = item.uniqueIdentifier
                guard let hotkey = menuBarManager.itemHotkeys[id], seen.insert(id).inserted else {
                    continue
                }
                rows.append(Row(
                    id: id,
                    name: item.displayName,
                    bundle: item.tag.namespace.description,
                    item: item,
                    hotkey: hotkey
                ))
            }
        }

        // Bound items whose app is not running, sorted for a stable order.
        let customNames = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        let absent = menuBarManager.itemHotkeys
            .filter { id, hotkey in hotkey.keyCombination != nil && !seen.contains(id) }
            .map { (id: $0.key, hotkey: $0.value, name: lastKnownName(for: $0.key, customNames: customNames)) }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        for entry in absent {
            rows.append(Row(
                id: entry.id,
                name: entry.name,
                bundle: bundle(forIdentifier: entry.id),
                item: nil,
                hotkey: entry.hotkey
            ))
        }

        return rows
    }

    private func rebuildRows() {
        rows = makeRows()
    }

    /// Best-effort display name for an absent item: the saved custom name if
    /// present, otherwise the title component of its identifier.
    private func lastKnownName(for identifier: String, customNames: [String: String]) -> String {
        if let custom = customNames[identifier], !custom.isEmpty {
            return custom
        }
        // identifier is "namespace:title[:index]"; surface the title component.
        let parts = identifier.split(separator: ":")
        if parts.count >= 2 {
            return String(parts[1])
        }
        return identifier
    }

    /// The bundle (namespace) component of an item identifier.
    private func bundle(forIdentifier identifier: String) -> String {
        String(identifier.split(separator: ":").first ?? "")
    }
}
