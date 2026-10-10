//
//  FoldedMenuBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import MenuBarModel
import SwiftUI
import ThawUI

/// Simple Mode folds sections into one surface; the Layout pane spaces them into cards.
struct FoldedMenuBar: View {
    enum Arrangement {
        /// Simple Mode stacks gapless bars on one surface with a section-name gutter.
        case folded
        /// Separate Layout pane cards with names above let long sections use the full width.
        case spaced
    }

    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    var arrangement: Arrangement = .folded

    /// Drag target published by LayoutBarContainer through layoutBarDragTargetChanged.
    @State private var dragTargetSection: MenuBarSection.Name?

    /// Fits "Always Hidden" at caption size in the shipped languages.
    private let gutterWidth: CGFloat = 92

    private var shape: some InsettableShape {
        RoundedRectangle(
            cornerRadius: ThawRadius.card,
            style: .continuous
        )
    }

    private var enabledSections: [MenuBarSection.Name] {
        MenuBarSection.Name.allCases.filter { section in
            appState.menuBarManager.section(withName: section)?.isEnabled == true
        }
    }

    var body: some View {
        switch arrangement {
        case .folded: folded
        case .spaced: spaced
        }
    }

    private var spaced: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.gutter) {
            ForEach(enabledSections, id: \.self) { section in
                VStack(alignment: .leading, spacing: ThawSpacing.compact) {
                    HStack(alignment: .firstTextBaseline) {
                        sectionName(section)
                        Spacer(minLength: ThawSpacing.base)
                        sortMenu(section)
                    }
                    .padding(.horizontal, ThawSpacing.tight)
                    LayoutBar(imageCache: appState.imageCache, section: section, chrome: .card)
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .layoutBarDragTargetChanged)
                ) { note in
                    noteDragTarget(note, for: section)
                }
            }
        }
        .layoutBarsLoading(itemManager: itemManager)
    }

    private var folded: some View {
        VStack(spacing: 0) {
            ForEach(Array(enabledSections.enumerated()), id: \.element) { index, section in
                if index > 0 {
                    foldLine
                }
                row(section)
            }
            // Thaw Bar Only is unplugged for now; restore this with the gate in MenuBarItemManager+ThawBarOnly.swift.
            // Always show this row while enabled so users can find it before adding items.
            // if itemManager.isThawBarOnlyEnabled {
            //     foldLine
            //     thawBarOnlyRow
            // }
            // if let suggestion = itemManager.thawBarOnlySuggestions.first {
            //     foldLine
            //     suggestionRow(for: suggestion)
            // }
        }
        .menuBarItemContainer(appState: appState)
        .containerShape(shape)
        .clipShape(shape)
        .contentShape([.interaction, .focusEffect], shape)
        .overlay {
            shape
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        }
        .thawShadow(.raised)
        .layoutBarsLoading(itemManager: itemManager)
    }

    private var foldLine: some View {
        Rectangle()
            .fill(.separator.opacity(0.5))
            .frame(height: 0.5)
    }

    private func row(_ section: MenuBarSection.Name) -> some View {
        HStack(spacing: 0) {
            sectionName(section)
                .frame(minWidth: gutterWidth, alignment: .leading)
                .padding(.leading, 12)
            LayoutBar(imageCache: appState.imageCache, section: section, chrome: .bare)
            sortMenu(section)
                .padding(.horizontal, 10)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .layoutBarDragTargetChanged)
        ) { note in
            noteDragTarget(note, for: section)
        }
    }

    /// The section's name, on an accent wash while a drag hovers its bar.
    private func sectionName(_ section: MenuBarSection.Name) -> some View {
        Text(section.localized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .background(
                Color.accentColor.opacity(dragTargetSection == section ? 0.22 : 0),
                in: RoundedRectangle(cornerRadius: 4)
            )
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    private func sortMenu(_ section: MenuBarSection.Name) -> some View {
        Menu {
            Button("Sort A–Z") {
                itemManager.sortItems(in: section, direction: .ascending)
            }
            Button("Sort Z–A") {
                itemManager.sortItems(in: section, direction: .descending)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Sort \(section.displayString) items")
        .help("Sort this section by name. Groups stay together.")
    }

    private func noteDragTarget(_ note: Notification, for section: MenuBarSection.Name) {
        let raw = note.userInfo?["section"] as? String
        let active = note.userInfo?["active"] as? Bool ?? false
        guard let raw,
              let name = MenuBarSection.Name(rawValue: raw),
              name == section
        else {
            if dragTargetSection == section {
                dragTargetSection = nil
            }
            return
        }
        dragTargetSection = active ? name : nil
    }

    // MARK: Thaw Bar Only

    /// Thaw Bar Only items have no menu bar order to drag; tiles only offer returning them.
    private var thawBarOnlyRow: some View {
        let items = itemManager.thawBarOnlyItems
        let images = OverflowFallbackIcon.resolvedImages(
            for: items,
            appState: appState,
            imageCache: appState.imageCache,
            section: { _ in .hidden }
        )
        return HStack(spacing: 0) {
            Text("Thaw Bar Only")
                .font(.caption.weight(.semibold))
                .fixedSize()
                .frame(minWidth: gutterWidth, alignment: .leading)
                .padding(.leading, 12)
                .accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Text("Right-click an item and choose Move to › Thaw Bar Only to keep it out of the menu bar.")
                    .font(.caption)
                    .foregroundStyle(ThawInk.supporting)
                    .lineLimit(2)
                    .padding(.horizontal, ThawSpacing.base)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: ThawSpacing.base) {
                        ForEach(items, id: \.uniqueIdentifier) { item in
                            thawBarOnlyTile(item, image: images[item.tag])
                        }
                    }
                    .padding(.horizontal, ThawSpacing.base)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(height: 48)
    }

    private func thawBarOnlyTile(_ item: MenuBarItem, image: MenuBarItemDisplayImage?) -> some View {
        Menu {
            Button("Move to Visible") {
                itemManager.returnFromThawBarOnly(item, to: .visible, appState: appState)
            }
            Button("Move to Hidden") {
                itemManager.returnFromThawBarOnly(item, to: .hidden, appState: appState)
            }
            Divider()
            Toggle("Show in Menu Bar", isOn: Binding(
                get: { appState.thawBarOnlyProxies.isEnabled(for: item) },
                set: { appState.thawBarOnlyProxies.setEnabled($0, for: item) }
            ))
            Button("Choose Icon…") {
                ItemIconPicker.present(for: item, appState: appState)
            }
        } label: {
            Group {
                if let image {
                    image.swiftUIImage
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "menubar.rectangle")
                }
            }
            .frame(height: 22)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help(item.displayName)
        .accessibilityLabel(item.displayName)
    }

    /// Offers a visible item macOS is not drawing a move to Thaw Bar Only.
    /// One at a time; the next one shows once this one is answered.
    private func suggestionRow(for item: MenuBarItem) -> some View {
        HStack(spacing: ThawSpacing.base) {
            Image(systemName: "eye.slash")
                .foregroundStyle(ThawInk.supporting)
            Text("macOS isn’t showing “\(item.displayName)” in the menu bar.")
                .font(.callout)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Move to Thaw Bar Only") {
                itemManager.moveToThawBarOnly(item, appState: appState)
            }
            .buttonStyle(.settingsGlass)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
