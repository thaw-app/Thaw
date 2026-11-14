//
//  ThawBarPreview.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import MenuBarModel
import SwiftUI
import ThawUI

/// Preview the bound layout with the items the real bar shows, in LayoutBarItemView tiles.
/// Center on wallpaper at real-panel proportions; bound height and scroll overflow instead of widening the page.
struct ThawBarPreview: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    let layout: ThawBarLayout
    let gridColumns: Int

    /// Whether the Thaw Bar is enabled on the display being edited.
    let useThawBar: Bool
    /// The display being edited, when it is a real connected screen. nil
    /// for the new-display template or a disconnected display.
    let displayID: CGDirectDisplayID?
    /// The menu-bar item spacing offset saved for the display being edited.
    let itemSpacingOffset: Double
    /// The Thaw Bar item size saved for the display being edited.
    let itemScale: Double
    /// The per-display choice; it only takes effect while Always Hidden is enabled.
    var useThawBarForAlwaysHidden = false

    private let maxBarHeight: CGFloat = 180

    /// The section previewed; Always Hidden is offered only while it is on.
    @State private var previewSection = MenuBarSection.Name.hidden

    /// The display the preview draws for, falling back to the first known
    /// screen for the new-display template.
    private var previewScreen: NSScreen? {
        if let displayID {
            return NSScreen.screen(for: displayID)
        }
        return NSScreen.managedScreens.first
    }

    /// Menu-bar height to use when no screen can be measured, matching the
    /// fallback the height estimate itself uses.
    private var fallbackMenuBarHeight: CGFloat {
        NSStatusBar.system.thickness
    }

    /// The raw menu-bar height the real panel scales every glyph to.
    private var itemMaxHeight: CGFloat? {
        guard let screen = previewScreen else { return nil }
        let height = screen.getMenuBarHeightEstimate()
        return height > 0 ? height : nil
    }

    /// The real panel's item spacing: the base gap plus the clamped offset.
    private var itemSpacing: CGFloat {
        let offset = CGFloat(itemSpacingOffset).rounded()
        return itemSizing.spacing(max(0, ThawSpacing.base + offset))
    }

    /// Scales the tiles the way the real panel scales its glyphs.
    private var itemSizing: ThawBarItemSize {
        ThawBarItemSize(fittingHeight: nil, scale: itemScale, displayScale: previewScreen?.backingScaleFactor ?? 2)
    }

    /// The real panel's vertical padding: a sliver on notched screens so a
    /// rounded shape clears the notch's corner radius, none elsewhere.
    private var verticalPadding: CGFloat {
        guard let screen = previewScreen else { return 0 }
        let hasRoundedShape = appState.appearanceManager.configuration.resolvedThawBarAppearance.hasRoundedShape
        return screen.hasNotch && hasRoundedShape ? 2 : 0
    }

    /// The content height the real panel bases its shape on: the menu-bar
    /// height, minus the inset when the shape is inset on a notched screen.
    private var contentHeight: CGFloat {
        guard let screen = previewScreen else { return fallbackMenuBarHeight }
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        let configuration = appState.appearanceManager.configuration
        if configuration.shapeKind != .noShape, configuration.isInset, screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.base) {
            if isAlwaysHiddenOn, !alwaysHiddenOnly {
                ThawPillPicker(
                    "Preview",
                    selection: $previewSection,
                    values: [MenuBarSection.Name.hidden, .alwaysHidden]
                ) { $0 == .hidden ? "Hidden" : "Always Hidden" }
            }
            ThawBarPreviewStage(displayID: displayID) {
                previewBar
            }

            ThawBarPreviewFooter(useThawBar: useThawBar, displayID: displayID, alwaysHiddenOnly: alwaysHiddenOnly)
        }
        .task(id: previewScreen?.displayID) {
            guard let screen = previewScreen else { return }
            await appState.menuBarManager.updateAverageColorInfoAsync(for: screen.displayID)
        }
    }

    // MARK: - Preview bar

    @ViewBuilder
    private var previewBar: some View {
        let items = previewItems
        let images = resolvedImages(for: items)
        let appearance = appState.appearanceManager.configuration.resolvedThawBarAppearance
        let screen = previewScreen
        let sample = screen.flatMap { appState.menuBarManager.averageColors[$0.displayID] }
        let clipShape = ThawBarBorderShape.thawBarClip(
            height: contentHeight,
            roundness: appearance.cornerRoundness
        )

        Group {
            if items.isEmpty {
                VStack(spacing: ThawSpacing.base) {
                    Text(shownSection == .alwaysHidden
                        ? "Nothing in Always Hidden to preview. Drag items into Always Hidden in Layout to see them here."
                        : "Nothing in Hidden to preview. Drag items into Hidden in Layout to see them here.")
                        .font(ThawType.detail)
                        .foregroundStyle(ThawInk.supporting)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Layout") {
                        SettingsSearchNavigation.selectSidebarPane(
                            .menuBarLayout,
                            navigationState: appState.navigationState
                        )
                    }
                    .buttonStyle(.settingsGlass)
                }
                .padding(.vertical, ThawSpacing.inset)
                .frame(maxWidth: 320)
            } else if layout == .horizontal {
                // Match the real panel: menu-bar-height row, base end gaps, and vertical padding only at a notch.
                arrangedItems(items, images: images)
                    .frame(height: contentHeight)
            } else {
                arrangedItems(items, images: images)
                    .frame(maxHeight: maxBarHeight)
            }
        }
        .padding(.horizontal, ThawSpacing.base)
        .padding(.vertical, verticalPadding)
        .foregroundStyle(ThawBarAppearanceForeground.resolve(
            appearance: appearance,
            sampledInfo: sample,
            adaptiveInfo: sample,
            palette: screen.flatMap { appState.menuBarManager.wallpaperPalettes[$0.displayID] },
            screen: screen
        ))
        .background {
            ThawBarAppearanceBackground(
                appearance: appearance,
                sampledColor: sample?.color,
                adaptiveColor: sample?.color,
                palette: screen.flatMap { appState.menuBarManager.wallpaperPalettes[$0.displayID] },
                shape: clipShape
            )
        }
        .clipShape(clipShape)
        .overlay {
            if appearance.hasBorder {
                ThawBarBorderShape.thawBarBorder(
                    height: contentHeight,
                    roundness: appearance.cornerRoundness,
                    borderWidth: CGFloat(appearance.borderWidth)
                )
                .stroke(lineWidth: CGFloat(appearance.borderWidth))
                .foregroundStyle(Color(cgColor: appearance.borderColor))
            }
        }
        .thawShadow(.raised, isVisible: appearance.hasShadow || appearance.backgroundHasShadow)
        .thawAnimation(ThawMotion.settle, value: layout)
        .thawAnimation(ThawMotion.quick, value: gridColumns)
        .thawAnimation(ThawMotion.quick, value: itemScale)
        .thawAnimation(ThawMotion.settle, value: appearance.cornerRoundness)
        .thawAnimation(ThawMotion.settle, value: appearance.hasBorder)
    }

    @ViewBuilder
    private func arrangedItems(
        _ items: [MenuBarItem],
        images: [MenuBarItemTag: NSImage]
    ) -> some View {
        // Hug items and scroll only on overflow so the bar keeps real-panel sizing rather than stretching to the pane.
        switch layout {
        case .horizontal:
            let row = HStack(spacing: itemSpacing) {
                ForEach(items, id: \.tag) { item in icon(for: images[item.tag]) }
            }
            ViewThatFits(in: .horizontal) {
                row
                ScrollView(.horizontal, showsIndicators: false) { row }
            }
        case .vertical:
            let column = VStack(spacing: itemSpacing) {
                ForEach(items, id: \.tag) { item in icon(for: images[item.tag]) }
            }
            ViewThatFits(in: .vertical) {
                column
                ScrollView(.vertical, showsIndicators: false) { column }
            }
        case .grid:
            let grid = itemGrid(items, images: images)
            ViewThatFits(in: .vertical) {
                grid
                ScrollView(.vertical, showsIndicators: false) { grid }
            }
        }
    }

    /// Rows of gridColumns items with aligned columns, the way the real
    /// panel lays out its grid.
    private func itemGrid(
        _ items: [MenuBarItem],
        images: [MenuBarItemTag: NSImage]
    ) -> some View {
        let columnCount = max(2, gridColumns)
        let rows = items.chunks(ofCount: columnCount)
        return Grid(horizontalSpacing: itemSpacing, verticalSpacing: itemSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.tag) { item in icon(for: images[item.tag]) }
                }
            }
        }
    }

    @ViewBuilder
    private func icon(for image: NSImage?) -> some View {
        if let image {
            // Preserve the editor tile's colors and, at 100%, its exact pixels.
            let size = itemSizing.scaledGlyphSize(image.size)
            Image(nsImage: image)
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .frame(width: size.width, height: size.height)
        } else {
            MenuBarItemPlaceholderIcon(length: itemSizing.rowHeight(fitting: itemMaxHeight ?? fallbackMenuBarHeight))
        }
    }

    // MARK: - Item sourcing

    private var isAlwaysHiddenOn: Bool {
        appState.settings.layout.isAlwaysHiddenSectionEnabled
    }

    private var alwaysHiddenOnly: Bool {
        !useThawBar && useThawBarForAlwaysHidden && isAlwaysHiddenOn
    }

    /// The section shown, falling back to Hidden once Always Hidden is turned off.
    private var shownSection: MenuBarSection.Name {
        alwaysHiddenOnly ? .alwaysHidden : (isAlwaysHiddenOn ? previewSection : .hidden)
    }

    private var previewItems: [MenuBarItem] {
        ThawBarItems.items(
            in: shownSection,
            itemManager: itemManager,
            switchedOff: appState.menuBarManager.nativeAppHidingExperiment.userSwitchedOffBundleIDs
        )
    }

    /// Share the editor renderer's captures, app-icon fallback, oversize rule, system-item padding, and tint.
    private func resolvedImages(for items: [MenuBarItem]) -> [MenuBarItemTag: NSImage] {
        items.reduce(into: [MenuBarItemTag: NSImage]()) { result, item in
            result[item.tag] = LayoutBarItemView.renderedTile(for: item, in: shownSection, appState: appState)
        }
    }
}
