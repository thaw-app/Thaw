//
//  LayoutEditorBars.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// The reorder editor: one row per section, with SwiftUI's own drag reordering
/// inside a row and between rows. A group is one tile and moves as a block.
struct LayoutEditorBars: View {
    private enum Metrics {
        static let rowHeight: CGFloat = 48
        static let tileSpacing: CGFloat = 2
    }

    @Environment(\.undoManager) private var undoManager
    let appState: AppState
    @State private var model: LayoutEditorModel
    @State private var rowWidth: CGFloat = 0

    init(appState: AppState) {
        self.appState = appState
        _model = State(initialValue: LayoutEditorModel(appState: appState))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.gutter) {
            ForEach(model.sections, id: \.self) { section in
                VStack(alignment: .leading, spacing: ThawSpacing.compact) {
                    Text(section.localized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, ThawSpacing.tight)
                        .accessibilityAddTraits(.isHeader)
                    row(section)
                }
            }
            if let refusal = appState.layoutFeedback.refusal {
                SettingsWarningPill(
                    title: LocalizedStringResource(String.LocalizationValue(refusal.title)),
                    message: LocalizedStringResource(String.LocalizationValue(refusal.message)),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    actionTitle: "Dismiss"
                ) {
                    appState.layoutFeedback.clear()
                }
            }
        }
        .reorderContainer(for: LayoutEditorOrder.Unit.self, in: MenuBarSection.Name.self) { difference in
            model.drop(difference, undoManager: undoManager)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func row(_ section: MenuBarSection.Name) -> some View {
        let units = model.units[section] ?? []
        return ScrollView(.horizontal) {
            HStack(spacing: Metrics.tileSpacing) {
                // Pushes icons to the trailing edge, as in the menu bar, and makes the
                // empty part of the row a drop target.
                Spacer(minLength: 0)
                ForEach(units) { unit in
                    LayoutEditorTile(unit: unit, items: model.items(of: unit), section: section, appState: appState)
                }
                .reorderable(collectionID: section)
            }
            .padding(.horizontal, ThawSpacing.base)
            .frame(minWidth: rowWidth, minHeight: Metrics.rowHeight)
            .contentShape(.rect)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.trailing)
        .frame(height: Metrics.rowHeight)
        .menuBarItemContainer(appState: appState)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
    }
}

/// One icon, or one group, in a row. Reading the image cache here keeps a recapture
/// from rebuilding the rows, which would otherwise happen during a drag.
private struct LayoutEditorTile: View {
    private enum Metrics {
        static let height: CGFloat = 36
        static let glyphHeight: CGFloat = 22
        static let spacing: CGFloat = 2
    }

    let unit: LayoutEditorOrder.Unit
    let items: [MenuBarItem]
    let section: MenuBarSection.Name
    let appState: AppState

    var body: some View {
        let images = OverflowFallbackIcon.resolvedImages(
            for: items,
            appState: appState,
            imageCache: appState.imageCache,
            section: { _ in section }
        )
        let name = items.map { MenuBarItemDisplayName.displayName(for: $0) }.formatted(.list(type: .and))
        HStack(spacing: Metrics.spacing) {
            ForEach(items, id: \.uniqueIdentifier) { item in
                Group {
                    if let image = images[item.tag] {
                        // Only scaled down: a stand-in's bare symbol stays at its own size.
                        MenuBarItemGlyph(image: image, fittingHeight: Metrics.glyphHeight, reinksCaptures: true)
                    } else {
                        Image(systemName: "menubar.rectangle")
                    }
                }
                .frame(height: Metrics.glyphHeight)
                .padding(.horizontal, ThawSpacing.capsuleInset)
            }
        }
        .padding(.horizontal, unit.isGroup ? 4 : 0)
        .frame(height: Metrics.height)
        .background {
            if unit.isGroup {
                Capsule().fill(.primary.opacity(0.1))
            }
        }
        .contentShape(.rect)
        .help(name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}
