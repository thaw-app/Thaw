//
//  MenuBarSearchList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// The results in ThawUI's launcher list. The keys stay with the panel; a
/// click selects, a double click opens.
struct MenuBarSearchList: View {
    @Environment(\.menuBarSearchPanel) private var panel
    @Environment(MenuBarSearchModel.self) private var model

    var body: some View {
        let results = model.results
        LauncherResultList(
            rows: results,
            selection: model.selectedIndex ?? -1,
            section: \.section,
            select: { model.selection = results[$0].id },
            activate: { panel?.activate(results[$0].item) },
            rowContent: { result, selected in
                MenuBarSearchRow(result: result, selected: selected)
            }
        )
    }
}

/// One item as a Floe palette row: picture, name, owning app. A rename puts
/// a field in the name's place.
private struct MenuBarSearchRow: View {
    @Environment(MenuBarSearchModel.self) private var model
    /// Grows with Larger Text, as the row's text does.
    @ScaledMetric(relativeTo: .body) private var rowHeight = PanelRow.height

    let result: MenuBarSearchResult
    let selected: Bool

    var body: some View {
        let item = result.item
        let name = MenuBarItemDisplayName.displayName(for: item)
        let isRenaming = model.renameSession?.targets(item) == true
        // PaletteRow's measures, with an image slot that widens for an item
        // as wide as the clock instead of squeezing it into a square.
        HStack(spacing: PanelRow.iconSpacing) {
            MenuBarSearchItemImage(item: item)
            if isRenaming {
                MenuBarItemRenameField(item: item)
                    .font(ThawType.body)
            } else {
                Text(name)
                    .font(ThawType.body)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !isRenaming, let ownerName = result.ownerName, ownerName != name {
                Text(verbatim: ownerName)
                    .font(ThawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, PanelRow.inset)
        .frame(minHeight: rowHeight)
        .modifier(SearchRowBackground(selected: selected))
        .accessibilityElement(children: isRenaming ? .contain : .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Item image

/// The item as Layout draws it: its menu bar picture, else its app icon. A
/// one-colour picture takes the row's ink, so a white glyph stays readable.
private struct MenuBarSearchItemImage: View {
    @Environment(AppState.self) private var appState
    /// Grows with Larger Text. Menu bar pictures don't: scaling them up blurs them.
    @ScaledMetric(relativeTo: .body) private var iconBox = PanelRow.iconBox

    /// A menu bar glyph's height, so pictures sit in the row as on the bar.
    private static let glyphHeight: CGFloat = 18
    /// The widest a picture is drawn, so a long text item leaves room for its name.
    private static let maxWidth: CGFloat = 120

    let item: MenuBarItem

    /// The glyph's height-fitted size, scaled down whole when it is wider than maxWidth.
    private static func drawnSize(of image: MenuBarItemDisplayImage) -> CGSize {
        let size = image.targetSize(fittingHeight: glyphHeight)
        guard size.width > maxWidth else { return size }
        return CGSize(width: maxWidth, height: size.height * maxWidth / size.width)
    }

    var body: some View {
        let image = OverflowFallbackIcon.resolvedImage(
            for: item,
            section: appState.menuBarManager.sectionController.section(for: item),
            appState: appState,
            capturedImage: appState.imageCache.image(for: item.tag)
        )
        Group {
            if let image {
                MenuBarItemGlyph(
                    image: image,
                    fittingHeight: Self.glyphHeight,
                    reinksCaptures: true,
                    drawnSize: Self.drawnSize(of: image)
                )
                .foregroundStyle(.primary)
            } else {
                MenuBarItemSourceIcon(item: item, length: iconBox)
            }
        }
        .frame(minWidth: iconBox, minHeight: iconBox)
    }
}

// MARK: - Source app icon

/// The icon of the app a menu bar item belongs to.
///
/// The same icon the Thaw Bar and Layout fall back to, so a system module such as
/// Bluetooth shows its own symbol. An unresolved owner gets a placeholder.
private struct MenuBarItemSourceIcon: View {
    /// Inset for a symbol, so it doesn't look larger than the app icons beside it.
    private static let symbolInset: CGFloat = 4

    let item: MenuBarItem
    let length: CGFloat

    var body: some View {
        if let sourceAppIcon = OverflowFallbackIcon.itemIcon(for: item) {
            Image(nsImage: sourceAppIcon)
                .resizable()
                .scaledToFit()
                .padding(sourceAppIcon.isTemplate ? Self.symbolInset : 0)
                .frame(width: length, height: length)
        } else {
            MenuBarItemPlaceholderIcon(length: length)
        }
    }
}

// MARK: - Rename field

/// The field a row shows in place of its name while renaming: Return saves, Escape cancels.
private struct MenuBarItemRenameField: View {
    @Environment(\.menuBarSearchPanel) private var panel
    @Environment(MenuBarSearchModel.self) private var model
    @FocusState private var isEditing: Bool

    let item: MenuBarItem

    var body: some View {
        TextField(item.autoDetectedName, text: renameDraft)
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .focused($isEditing)
            .textContentType(.none)
            .autocorrectionDisabled(true)
            .onSubmit {
                panel?.commitRename()
            }
            .onExitCommand {
                model.renameSession = nil
            }
            .onAppear {
                isEditing = true
            }
            .onDisappear {
                isEditing = false
            }
    }

    /// Binding into the draft of the active rename. Writes that arrive after
    /// the session has ended are dropped.
    private var renameDraft: Binding<String> {
        Binding(
            get: { model.renameSession?.draft ?? "" },
            set: { model.renameSession?.draft = $0 }
        )
    }
}
