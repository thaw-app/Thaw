//
//  MenuBarSearchRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - MenuBarSearchListContent

/// What a row of the search list draws.
///
/// SectionedList paints selection and hover, so they cannot drift from
/// keyboard navigation.
enum MenuBarSearchListContent: View {
    case header(MenuBarSection.Name)
    /// A plain text heading not backed by a section, currently only the
    /// recents header.
    case label(String)
    /// An item in the inspector: owning app, name, and a preview of how the
    /// item is drawn in the menu bar.
    case item(MenuBarItem)
    /// An item in the launcher: owning app, name, and the owning app's name
    /// underneath when it says something the item's name doesn't.
    case launcherItem(MenuBarItem, ownerName: String?)
    /// An item in the assisted palette: the launcher's row, enlarged.
    case assistedItem(MenuBarItem, ownerName: String?)

    var body: some View {
        switch self {
        case let .header(name):
            Text(name.localized)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ThawSpacing.row)
                .padding(.leading, ThawSpacing.compact)
        case let .label(text):
            Text(text)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ThawSpacing.row)
                .padding(.leading, ThawSpacing.compact)
        case let .item(item):
            MenuBarItemRow(item: item)
        case let .launcherItem(item, ownerName):
            paletteRow(item, ownerName: ownerName, presentation: .launcher)
        case let .assistedItem(item, ownerName):
            paletteRow(item, ownerName: ownerName, presentation: .assisted)
        }
    }

    /// The launcher row at one face's proportions; a face with no rowMetrics
    /// draws nothing.
    @ViewBuilder
    private func paletteRow(
        _ item: MenuBarItem,
        ownerName: String?,
        presentation: SearchPresentation
    ) -> some View {
        if let metrics = presentation.rowMetrics {
            PaletteItemRow(item: item, ownerName: ownerName, metrics: metrics)
        }
    }
}

// MARK: - Source app icon

/// The icon of the app a menu bar item belongs to.
///
/// System agents show Control Center's icon; an unresolved owner gets a
/// placeholder.
private struct MenuBarItemSourceIcon: View {
    let item: MenuBarItem
    let length: CGFloat

    private var sourceAppIcon: NSImage? {
        switch item.tag.namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return ControlCenterIcon.image
        default:
            guard let sourcePID = item.sourcePID else {
                return nil
            }
            return OverflowFallbackIcon.cachedAppIcon(forPID: sourcePID)
        }
    }

    var body: some View {
        if let sourceAppIcon {
            Image(nsImage: sourceAppIcon)
                .resizable()
                .scaledToFit()
                .frame(width: length, height: length)
        } else {
            MenuBarItemPlaceholderIcon(length: length)
        }
    }
}

/// The stand-in tile for an item whose owning app cannot be resolved.
///
/// Its own view so the environment read below stays off the common path.
/// No shadow, because the real icons beside it carry none.
private struct MenuBarItemPlaceholderIcon: View {
    @Environment(\.self) private var environment

    let length: CGFloat

    /// Measured against the accent: white on Thaw's light amber is only 2.1:1.
    /// The shared foreground switch keeps both sides above 4.58:1.
    private var glyphColor: Color {
        let accent = Color.accentColor.resolve(in: environment)
        let luminance = ForegroundContrast.relativeLuminance(
            linearRed: Double(accent.linearRed),
            linearGreen: Double(accent.linearGreen),
            linearBlue: Double(accent.linearBlue)
        )
        return ForegroundContrast.prefersDarkContent(onLuminance: luminance) ? .black : .white
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.gradient)
            .strokeBorder(Color.primary.gradient.quaternary)
            .overlay {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(glyphColor)
                    .padding(3)
            }
            .padding(2.5)
            .frame(width: length, height: length)
    }
}

// MARK: - Inspector row

/// One menu bar item in the inspector list: owning app, name, and a preview of
/// how the item is drawn in the menu bar. Renames happen inline here.
private struct MenuBarItemRow: View {
    private static let iconLength: CGFloat = 26

    @Environment(\.menuBarSearchPanel) private var panel
    @Environment(AppState.self) private var appState
    @Environment(MenuBarItemImageCache.self) private var imageCache
    @Environment(MenuBarSearchModel.self) private var model
    @FocusState private var isEditing: Bool

    let item: MenuBarItem

    var body: some View {
        HStack {
            if model.renameSession?.targets(item) == true {
                renameField
            } else {
                Label {
                    // Memoized: avoids an NSRunningApplication per evaluation.
                    Text(MenuBarItemDisplayName.displayName(for: item))
                } icon: {
                    MenuBarItemSourceIcon(item: item, length: Self.iconLength)
                }
            }
            Spacer()
            itemPreview
        }
        .padding(ThawSpacing.compact)
        // Lift only: SectionedList already paints the hover wash.
        .thawHoverLift()
    }

    private var renameField: some View {
        HStack(spacing: ThawSpacing.base) {
            MenuBarItemSourceIcon(item: item, length: Self.iconLength)
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
    }

    /// Binding into the draft of the active rename. Writes that arrive after
    /// the session has ended are dropped.
    private var renameDraft: Binding<String> {
        Binding(
            get: { model.renameSession?.draft ?? "" },
            set: { model.renameSession?.draft = $0 }
        )
    }

    /// The item as it appears in the menu bar, over the same backdrop.
    private var itemPreview: some View {
        let previewShape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return Group {
            if let capture = imageCache.capturesByTag[item.tag],
               let trimmed = capture.horizontallyTrimmedCGImage
            {
                Image(decorative: trimmed, scale: capture.scale)
            } else {
                Color.clear
            }
        }
        .frame(width: item.bounds.width, height: Self.iconLength)
        .menuBarItemContainer(appState: appState, colorInfo: model.averageColorInfo)
        .clipShape(previewShape)
        .overlay {
            previewShape
                .strokeBorder(.quaternary)
        }
    }
}

// MARK: - Launcher row

/// One menu bar item in a launcher list: owning app icon, display name, and
/// the owning app's name when it adds something.
///
/// No preview: the launchers never run the capture pass. Sized by
/// SearchPresentation.rowMetrics.
private struct PaletteItemRow: View {
    let item: MenuBarItem
    let ownerName: String?
    let metrics: SearchPresentation.RowMetrics

    var body: some View {
        if metrics.combinesAccessibilityChildren {
            // VoiceOver reads one label instead of walking the icon, the name,
            // and the owner name as separate elements.
            row.accessibilityElement(children: .combine)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: metrics.iconSpacing) {
            MenuBarItemSourceIcon(item: item, length: metrics.iconLength)
            VStack(alignment: .leading, spacing: metrics.textSpacing) {
                // Memoized: avoids an NSRunningApplication per row per keystroke.
                Text(MenuBarItemDisplayName.displayName(for: item))
                    .font(metrics.nameFont)
                    .lineLimit(metrics.nameLineLimit)
                if let ownerName {
                    Text(ownerName)
                        .font(metrics.ownerFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.padding)
        .frame(minHeight: metrics.minHeight)
    }
}
