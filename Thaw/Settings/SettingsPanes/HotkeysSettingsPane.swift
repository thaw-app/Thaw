//
//  HotkeysSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: HotkeysSettings

    var body: some View {
        IceForm {
            IceSection("Menu Bar Sections") {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
            }
            IceSection("Menu Bar Items") {
                hotkeyRecorder(forAction: .searchMenuBarItems)
                MenuBarItemHotkeyList(
                    menuBarManager: appState.menuBarManager,
                    itemManager: appState.itemManager,
                    imageCache: appState.imageCache
                )
            }
            if !appState.profileManager.profiles.isEmpty {
                IceSection("Profiles") {
                    ForEach(appState.profileManager.profiles) { meta in
                        profileHotkeyRecorder(for: meta)
                    }
                }
            }
            IceSection("Other") {
                hotkeyRecorder(forAction: .enableIceBar)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = settings.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text("Toggle the hidden section")
                case .toggleAlwaysHiddenSection:
                    Text("Toggle the always-hidden section")
                case .searchMenuBarItems:
                    Text("Search menu bar items")
                case .enableIceBar:
                    Text("Enable the \(Constants.displayName) Bar")
                case .toggleApplicationMenus:
                    Text("Toggle application menus")
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

/// A collapsible list of per-item hotkey recorders. Each row pairs a menu bar
/// item (icon and name) with a recorder that opens the item's menu when the
/// hotkey fires. Items with a saved binding whose owning app is not currently
/// running are still listed, marked unavailable, so the binding can be cleared.
private struct MenuBarItemHotkeyList: View {
    @ObservedObject var menuBarManager: MenuBarManager
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let rows = makeRows()
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
                                // Claim the name's full width so it is not
                                // truncated by the flexible spacer column.
                                .fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(row.item != nil ? .primary : .secondary)
                            Text(row.bundle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                // Claim the bundle's full width so the flexible
                                // spacer column below does not compress it.
                                .fixedSize(horizontal: true, vertical: false)
                            // Flexible spacer column: absorbs the slack so the
                            // name and bundle stay compact on the left while the
                            // recorder is pushed to the trailing edge.
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
        // Tell the image cache whether this list is visible so it only runs the
        // live capture loop while the disclosure is expanded.
        .onChange(of: isExpanded, initial: true) { _, expanded in
            imageCache.setItemHotkeyListExpanded(expanded)
        }
        .onDisappear {
            imageCache.setItemHotkeyListExpanded(false)
        }
        .task(id: isExpanded) {
            // Item images for the hidden and always-hidden sections are not
            // captured until something requests them. Prewarm all sections when
            // the list is expanded so off-screen items show their real icon.
            guard isExpanded else { return }
            await imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        }
    }

    @ViewBuilder
    private func iconView(for row: Row) -> some View {
        if let image = row.item.flatMap({ imageCache.images[$0.tag]?.nsImage }) {
            // Render at the captured size (the nsImage already carries the
            // item's scaled point size), matching the Layout pane rather than
            // forcing a square that distorts wide items like Clock or Outlook.
            Image(nsImage: image)
        } else {
            // No captured image for an absent item; show a neutral placeholder
            // sized to roughly the menu bar item height.
            Image(systemName: "questionmark.square.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
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

        // Present items grouped by section (visible, hidden, always-hidden),
        // reversed within each section so the rightmost menu bar item (e.g. the
        // clock) appears first.
        for section in MenuBarSection.Name.allCases {
            for item in itemManager.itemCache.managedItems(for: section).reversed()
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

        // Configured-but-absent items (owning app not currently running).
        // itemHotkeys is an unordered dictionary, so sort by name (then id) for
        // a stable row order across renders.
        let absent = menuBarManager.itemHotkeys
            .filter { id, hotkey in hotkey.keyCombination != nil && !seen.contains(id) }
            .map { (id: $0.key, hotkey: $0.value, name: lastKnownName(for: $0.key)) }
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

    /// Best-effort display name for an absent item: the saved custom name if
    /// present, otherwise the title component of its identifier.
    private func lastKnownName(for identifier: String) -> String {
        let customNames = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
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
