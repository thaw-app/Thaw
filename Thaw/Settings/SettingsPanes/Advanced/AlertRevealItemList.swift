//
//  AlertRevealItemList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// Keyboard-accessible counterpart to the layout bar's "Reveal When Its Icon
/// Changes" menu entry.
///
/// Lists only concealed items, since the watcher skips the visible section.
/// Opt-ins for departed items stay listed so they can be withdrawn before
/// the app's next launch.
struct AlertRevealItemList: View {
    /// One row: a concealable item, or an opt-in whose item has since left.
    private struct Row: Identifiable {
        let id: String
        let name: String
        let isPresent: Bool
    }

    @Environment(AppState.self) private var appState

    /// Local copy of the Defaults-backed set, which is not observable;
    /// re-read on appear.
    @State private var enabledIdentifiers: Set<String> = []

    var body: some View {
        content
            .onAppear { enabledIdentifiers = MenuBarItemAlertReveals.identifiers() }
    }

    @ViewBuilder
    private var content: some View {
        let rows = rows()
        if rows.isEmpty {
            Text("Hide an item first. Anything in Hidden or Always Hidden can be set to reappear when its icon changes.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(rows) { row in
                Toggle(isOn: binding(for: row.id)) {
                    if row.isPresent {
                        Text(row.name)
                    } else {
                        // Nothing resolves a display name for an absent item,
                        // so the raw identifier is all there is to show.
                        Text("\(row.name) (not currently in the menu bar)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func rows() -> [Row] {
        let cache = appState.itemManager.itemCache
        let concealable = cache[.hidden] + cache[.alwaysHidden]

        var seen = Set<String>()
        var rows = concealable.compactMap { item -> Row? in
            let identifier = item.tag.tagIdentifier
            guard seen.insert(identifier).inserted else { return nil }
            return Row(
                id: identifier,
                name: MenuBarItemDisplayName.displayName(for: item),
                isPresent: true
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        rows += enabledIdentifiers
            .subtracting(seen)
            .sorted()
            .map { Row(id: $0, name: $0, isPresent: false) }

        return rows
    }

    private func binding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { enabledIdentifiers.contains(identifier) },
            set: { isEnabled in
                MenuBarItemAlertReveals.setEnabled(isEnabled, for: identifier)
                enabledIdentifiers = MenuBarItemAlertReveals.identifiers()
            }
        )
    }
}
