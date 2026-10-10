//
//  ThawBarContentView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import SwiftUI
import ThawCapture
import ThawUI

/// What the keyboard highlight has to follow: the item count and layout.
private struct KeyboardLayoutKey: Equatable {
    let count: Int
    let layout: ThawBarLayout
    let columns: Int
}

struct ThawBarContentView: View {
    let appState: AppState
    let colorManager: ThawBarColorManager
    let keyboardFocus: ThawBarKeyboardFocus
    let itemManager: MenuBarItemManager
    let imageCache: MenuBarItemImageCache
    let menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0
    @State private var cacheGracePeriodActive = true
    @State private var loadingTimedOut = false
    @State private var visibleControlItemState: ControlItem.HidingState

    let visibleControlItem: ControlItem?
    let screen: NSScreen
    let section: MenuBarSection.Name
    /// Set for both small bars, which carry only the Thaw Bar Only items.
    let showsOnlyThawBarOnlyItems: Bool
    /// A folder's members, when the panel shows one folder.
    let folderMembers: [String]?

    init(
        appState: AppState,
        colorManager: ThawBarColorManager,
        keyboardFocus: ThawBarKeyboardFocus,
        itemManager: MenuBarItemManager,
        imageCache: MenuBarItemImageCache,
        menuBarManager: MenuBarManager,
        visibleControlItem: ControlItem?,
        screen: NSScreen,
        section: MenuBarSection.Name,
        showsOnlyThawBarOnlyItems: Bool,
        folderMembers: [String]?
    ) {
        self.appState = appState
        self.colorManager = colorManager
        self.keyboardFocus = keyboardFocus
        self.itemManager = itemManager
        self.imageCache = imageCache
        self.menuBarManager = menuBarManager
        self.visibleControlItem = visibleControlItem
        self.screen = screen
        self.section = section
        self.showsOnlyThawBarOnlyItems = showsOnlyThawBarOnlyItems
        self.folderMembers = folderMembers
        self._visibleControlItemState = State(initialValue: visibleControlItem?.state ?? .hideSection)
    }

    private var visibleControlItemStatePublisher: AnyPublisher<ControlItem.HidingState, Never> {
        guard let visibleControlItem else {
            return Empty().eraseToAnyPublisher()
        }
        return visibleControlItem.$state.eraseToAnyPublisher()
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
    }

    private var thawBarAppearance: ResolvedThawBarAppearance {
        configuration.resolvedThawBarAppearance
    }

    private var displaySettings: DisplaySettingsManager {
        appState.settings.displaySettings
    }

    private var layout: ThawBarLayout {
        displaySettings.configuration(for: screen.displayID).thawBarLayout
    }

    private var gridColumns: Int {
        displaySettings.configuration(for: screen.displayID).gridColumns
    }

    private var itemSpacing: CGFloat {
        let offset = CGFloat(displaySettings.configuration(for: screen.displayID).itemSpacingOffset).rounded()
        return max(0, ThawSpacing.base + offset)
    }

    private var horizontalPadding: CGFloat {
        ThawSpacing.base
    }

    private var verticalPadding: CGFloat {
        screen.hasNotch && thawBarAppearance.hasRoundedShape ? 2 : 0
    }

    private var contentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        if configuration.shapeKind != .noShape, configuration.isInset, screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var itemMaxHeight: CGFloat? {
        // Preserve native icon height regardless of shape insets; the clip trims overflow.
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        return menuBarHeight > 0 ? menuBarHeight : nil
    }

    /// Reuse resolved images for grid column widths instead of resolving twice.
    private func columnWidths(
        items: [MenuBarItem],
        using images: [MenuBarItemTag: MenuBarItemDisplayImage]
    ) -> [CGFloat] {
        guard let maxHeight = itemMaxHeight, maxHeight > 0 else { return [] }
        let rows = stride(from: 0, to: items.count, by: gridColumns).map { start in
            Array(items[start ..< Swift.min(start + gridColumns, items.count)])
        }
        return (0 ..< gridColumns).map { col in
            rows.compactMap { row in
                guard col < row.count else { return nil }
                guard let image = images[row[col].tag] else { return nil }
                return image.targetSize(fittingHeight: maxHeight).width
            }.max() ?? 0
        }
    }

    /// Cap vertical and grid content to keep the panel within the visible screen.
    private var maxContentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        let available = (screen.frame.maxY - menuBarHeight) - screen.visibleFrame.minY
        let totalPadding: CGFloat = 10 + verticalPadding * 2
        return max(available - totalPadding, contentHeight)
    }

    private func totalContentHeight(items: [MenuBarItem]) -> CGFloat {
        switch layout {
        case .horizontal:
            return contentHeight
        case .vertical:
            return CGFloat(items.count) * contentHeight
        case .grid:
            let rowCount = Int(ceil(Double(items.count) / Double(gridColumns)))
            return CGFloat(rowCount) * contentHeight
        }
    }

    private var clipShape: ThawBarBorderShape {
        ThawBarBorderShape.thawBarClip(height: contentHeight, hasRoundedShape: thawBarAppearance.hasRoundedShape)
    }

    private func itemView(for item: MenuBarItem, image: MenuBarItemDisplayImage?, at index: Int) -> ThawBarItemView {
        ThawBarItemView(
            itemManager: itemManager,
            menuBarManager: menuBarManager,
            item: item,
            section: section,
            displayID: screen.displayID,
            maxHeight: itemMaxHeight,
            tooltipDelay: appState.settings.advanced.tooltipDelay,
            displayImage: image,
            isKeyboardFocused: keyboardFocus.index == index,
            activationRequest: keyboardFocus.activationRequest,
            onPointerEntered: { keyboardFocus.pointerEntered(index) }
        )
    }

    /// Resolve each image once by tag, using this bar's single section.
    private func resolvedImages(items: [MenuBarItem]) -> [MenuBarItemTag: MenuBarItemDisplayImage] {
        OverflowFallbackIcon.resolvedImages(
            for: items,
            appState: appState,
            imageCache: imageCache,
            visibleControlItemState: visibleControlItemState,
            section: { _ in section }
        )
    }

    /// Concealed sections can still render from app icons when captures fail.
    private var canShowItemsWithoutCaptures: Bool {
        OverflowFallbackIcon.supportsMissingCaptureFallback(for: section)
    }

    var body: some View {
        // Thaw Bar Only items have a bar of their own, opened from their icon.
        let items = if let folderMembers {
            folderMembers.compactMap { identifier in
                itemManager.managedItems.first {
                    MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier) == identifier
                }
            }
        } else if showsOnlyThawBarOnlyItems {
            itemManager.thawBarOnlyItems
        } else {
            itemManager.managedItems(for: section).filter { !itemManager.isThawBarOnly($0) }
        }
        ZStack {
            ThawBarChrome(
                colorManager: colorManager,
                menuBarManager: menuBarManager,
                screen: screen,
                appearance: thawBarAppearance,
                overridesMenuBar: configuration.thawBarAppearance.overridesMenuBar,
                shape: clipShape
            ) {
                Group {
                    if layout == .horizontal {
                        content(items: items).frame(height: contentHeight)
                    } else {
                        content(items: items)
                            .frame(height: min(totalContentHeight(items: items), maxContentHeight))
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
            }

            if thawBarAppearance.hasBorder {
                // Trace the clip; omit the square-corner top edge to avoid the display's rounded-corner clipping.
                ThawBarBorderShape.thawBarBorder(
                    height: contentHeight,
                    hasRoundedShape: thawBarAppearance.hasRoundedShape,
                    borderWidth: CGFloat(thawBarAppearance.borderWidth)
                )
                .stroke(lineWidth: CGFloat(thawBarAppearance.borderWidth))
                .foregroundStyle(Color(cgColor: thawBarAppearance.borderColor))
            }
        }
        // The 5pt inset is what makes this read as a floating bar.
        .padding(5)
        // The panel supplies the shadow; another here enters its alpha mask and adds a second contour.
        .frame(maxWidth: screen.frame.width)
        .fixedSize(horizontal: true, vertical: layout == .horizontal)
        // Keep keyboard focus in range and map arrows to the current layout.
        .onChange(of: KeyboardLayoutKey(count: items.count, layout: layout, columns: gridColumns), initial: true) { _, key in
            let arrangement: ThawBarKeyboardFocus.Arrangement = switch key.layout {
            case .horizontal: .row
            case .vertical: .column
            case .grid: .grid(columns: key.columns)
            }
            keyboardFocus.update(itemCount: key.count, arrangement: arrangement)
        }
        .onChange(of: thawBarAppearance, initial: true) { _, appearance in
            menuBarManager.thawBarPanel.hasShadow = appearance.hasShadow || appearance.backgroundHasShadow
            menuBarManager.thawBarPanel.invalidateShadow()
        }
        .onAppear {
            Self.diagLog.notice("""
            ThawBarContentView appeared: \
            displayID=\(screen.displayID) \
            backingScaleFactor=\(Double(screen.backingScaleFactor)) \
            hasNotch=\(screen.hasNotch) \
            contentHeight=\(Double(contentHeight)) \
            itemMaxHeight=\(Double(itemMaxHeight ?? 0)) \
            menuBarHeight=\(Double(screen.getMenuBarHeightEstimate())) \
            layout=\(String(describing: layout)) \
            items=\(items.count) \
            section=\(section.logString)
            """)
        }
        .onFrameChange(update: $frame)
        .onReceive(visibleControlItemStatePublisher) { state in
            visibleControlItemState = state
        }
        .task(id: section) {
            cacheGracePeriodActive = true
            loadingTimedOut = false
            try? await Task.sleep(for: .milliseconds(600))
            cacheGracePeriodActive = false
            try? await Task.sleep(for: .seconds(2))
            loadingTimedOut = true
        }
    }

    private static let diagLog = DiagLog(category: "ThawBar.Content")

    /// Opens the permissions settings pane, hiding the current section first.
    private func openPermissionsSettings() {
        menuBarManager.section(withName: section)?.hide()
        appState.navigationState.settingsNavigationIdentifier = .privacy
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    private func openLayoutEditor() {
        menuBarManager.section(withName: section)?.hide()
        HotkeyAction.toggleLayoutEditor.perform(appState: appState)
    }

    private var loadingRow: some View {
        Text("Loading menu bar items…")
            .transition(.opacity)
    }

    /// Offer permissions settings on load failure, since missing permission is a common cause.
    @ViewBuilder
    private func failureRow(_ message: Text) -> some View {
        message
            .transition(.opacity)
        Button {
            openPermissionsSettings()
        } label: {
            // Link blue may miss 4.5:1 on sampled wallpaper; use an underline for the affordance.
            Text("Check permissions")
                .underline()
                .padding(.horizontal, ThawSpacing.tight)
                .padding(.vertical, ThawSpacing.hairline)
        }
        .buttonStyle(.plain)
        .thawRowHover()
    }

    @ViewBuilder
    private func content(items: [MenuBarItem]) -> some View {
        // App-icon fallbacks keep the bar usable with Accessibility alone, without a screen-recording gate.
        if section == .alwaysHidden || section == .hidden, items.isEmpty {
            HStack {
                if cacheGracePeriodActive {
                    loadingRow
                } else {
                    Text(section == .alwaysHidden
                        ? "Nothing in Always Hidden yet."
                        : "Nothing in Hidden yet.")
                        .transition(.opacity)
                    Button {
                        openLayoutEditor()
                    } label: {
                        // Use an underline instead of link blue for wallpaper contrast, as in failureRow.
                        Text("Open Layout")
                            .underline()
                            .padding(.horizontal, ThawSpacing.tight)
                            .padding(.vertical, ThawSpacing.hairline)
                    }
                    .buttonStyle(.plain)
                    .thawRowHover()
                }
            }
            .thawAnimation(ThawMotion.quick, value: cacheGracePeriodActive)
            .padding(.horizontal, 10)
            .onChange(of: cacheGracePeriodActive) {
                Self.diagLog.debug("ThawBar content: grace period changed to \(self.cacheGracePeriodActive) for section \(self.section.logString), items still empty: \(items.isEmpty)")
            }
            .onChange(of: loadingTimedOut) {
                // Empty sections are not stalled loads; the timeout is diagnostic only here.
                Self.diagLog.debug("ThawBar content: loading timeout changed to \(self.loadingTimedOut) for section \(self.section.logString), items still empty: \(items.isEmpty)")
            }
            .onAppear {
                Self.diagLog.debug("ThawBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "No items")' for section \(self.section.logString) (grace period active: \(self.cacheGracePeriodActive))")
            }
        } else if itemManager.hasNoManagedItems {
            HStack {
                if loadingTimedOut {
                    failureRow(Text("Couldn’t load menu bar items"))
                } else {
                    loadingRow
                }
            }
            .thawAnimation(ThawMotion.quick, value: loadingTimedOut)
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("ThawBar content: loading timeout changed to \(self.loadingTimedOut), itemCache.managedItems is still EMPTY")
            }
            .onAppear {
                Self.diagLog.warning("ThawBar content: showing 'Loading menu bar items…', itemCache.managedItems is EMPTY. This means the item cache has never been populated.")
            }
        } else if imageCache.hasNoRenderableItems(in: section), !canShowItemsWithoutCaptures {
            HStack {
                if loadingTimedOut, !cacheGracePeriodActive {
                    // Final state: no further automatic retry.
                    failureRow(Text("Couldn’t show menu bar items"))
                } else {
                    loadingRow
                }
            }
            .thawAnimation(ThawMotion.quick, value: cacheGracePeriodActive)
            .thawAnimation(ThawMotion.quick, value: loadingTimedOut)
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("ThawBar content: hasNoRenderableItems timeout changed to \(self.loadingTimedOut) for section \(self.section.logString)")
            }
            .onAppear {
                Self.diagLog.warning("ThawBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "Unable to display")' for section \(self.section.logString), imageCache.hasNoRenderableItems=true (grace period active: \(self.cacheGracePeriodActive), loadingTimedOut: \(self.loadingTimedOut), cached images count: \(self.imageCache.capturesByTag.count), items in section: \(self.itemManager.itemCache[self.section].count))")
            }
        } else {
            let images = resolvedImages(items: items)
            Group {
                switch layout {
                case .horizontal:
                    ScrollView(.horizontal) {
                        HStack(spacing: itemSpacing) {
                            ForEach(Array(items.enumerated()), id: \.element.uniqueIdentifier) { index, item in
                                itemView(for: item, image: images[item.tag], at: index)
                            }
                        }
                        .frame(height: contentHeight)
                    }
                    .environment(\.isScrollEnabled, frame.width == screen.frame.width)
                    .defaultScrollAnchor(.trailing)

                case .vertical:
                    ScrollView(.vertical) {
                        VStack(spacing: itemSpacing) {
                            ForEach(Array(items.enumerated()), id: \.element.uniqueIdentifier) { index, item in
                                itemView(for: item, image: images[item.tag], at: index)
                            }
                        }
                    }

                case .grid:
                    let columnWidths = self.columnWidths(items: items, using: images)
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            let rows = stride(from: 0, to: items.count, by: gridColumns).map { start in
                                Array(items[start ..< Swift.min(start + gridColumns, items.count)])
                            }
                            ForEach(Array(rows.enumerated()), id: \.element.first?.uniqueIdentifier) { rowIndex, rowItems in
                                HStack(spacing: itemSpacing) {
                                    ForEach(Array(rowItems.enumerated()), id: \.element.uniqueIdentifier) { colIndex, item in
                                        if rows.count > 1 {
                                            itemView(for: item, image: images[item.tag], at: rowIndex * gridColumns + colIndex)
                                                .frame(width: columnWidths[colIndex], alignment: .center)
                                        } else {
                                            itemView(for: item, image: images[item.tag], at: rowIndex * gridColumns + colIndex)
                                        }
                                    }
                                    // Pad partial rows only in multi-row grids to align with the columns above.
                                    if rows.count > 1, rowItems.count < gridColumns {
                                        ForEach(rowItems.count ..< gridColumns, id: \.self) { colIndex in
                                            Color.clear
                                                .frame(width: columnWidths[colIndex], height: contentHeight)
                                        }
                                    }
                                }
                                .frame(height: contentHeight)
                            }
                        }
                    }
                }
            }
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }
}

// MARK: - ThawBarChrome

/// Isolate color-driven foreground, background, and clipping so sample ticks do not rebuild the item grid.
private struct ThawBarChrome<Content: View>: View {
    let colorManager: ThawBarColorManager
    let menuBarManager: MenuBarManager
    let screen: NSScreen
    let appearance: ResolvedThawBarAppearance
    let overridesMenuBar: Bool
    let shape: ThawBarBorderShape
    @ViewBuilder let content: Content

    var body: some View {
        let sample = ThawBarColorManager.backgroundSample(
            for: screen.displayID,
            overridesMenuBar: overridesMenuBar,
            sharedSamples: menuBarManager.averageColors,
            localSample: colorManager.colorDisplayID == screen.displayID ? colorManager.colorInfo : nil
        )
        content
            .foregroundStyle(ThawBarAppearanceForeground.resolve(
                appearance: appearance,
                sampledInfo: sample,
                adaptiveInfo: menuBarManager.averageColors[screen.displayID],
                palette: menuBarManager.wallpaperPalettes[screen.displayID],
                screen: screen
            ))
            .background {
                ThawBarAppearanceBackground(
                    appearance: appearance,
                    sampledColor: sample?.color,
                    adaptiveColor: menuBarManager.averageColors[screen.displayID]?.color,
                    palette: menuBarManager.wallpaperPalettes[screen.displayID],
                    shape: shape
                )
            }
            .clipShape(shape)
    }
}
