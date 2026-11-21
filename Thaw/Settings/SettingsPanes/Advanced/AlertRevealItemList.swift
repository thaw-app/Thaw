//
//  AlertRevealItemList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import MenuBarModel
import SwiftUI
import ThawUI

/// Keyboard-accessible counterpart to the layout bar's "Show When Its Icon
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

    /// The saved choice, which is not observable: read again on appear, and in the
    /// settings process whenever the app saves one.
    private var choices: AlertRevealChoices {
        appState.alertRevealWatcher.choices
    }

    var body: some View {
        content
            .onAppear { choices.reload() }
    }

    @ViewBuilder
    private var content: some View {
        if choices.awaitsItems {
            // Without the app's items nothing here is known to be hidden, or to have left.
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            list
        }
    }

    @ViewBuilder
    private var list: some View {
        let rows = rows()
        if rows.isEmpty {
            Text("Hide an item first. Anything in Hidden or Always Hidden can be set to reappear when its icon changes.")
                .foregroundStyle(.secondary)
                .font(ThawType.detail)
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

        var rows = concealable.uniqued(on: \.tag.tagIdentifier).map { item in
            Row(
                id: item.tag.tagIdentifier,
                name: MenuBarItemDisplayName.displayName(for: item),
                isPresent: true
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        rows += choices.identifiers
            .subtracting(rows.map(\.id))
            .sorted()
            .map { Row(id: $0, name: $0, isPresent: false) }

        return rows
    }

    private func binding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { choices.identifiers.contains(identifier) },
            set: { choices.setEnabled($0, for: identifier) }
        )
    }
}
