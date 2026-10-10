//
//  IceBar.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Algorithms
import Combine
import SwiftUI

// MARK: - IceBarPanel

final class IceBarPanel: NSPanel {
    private let diagLog = DiagLog(category: "IceBarPanel")
    private weak var appState: AppState?

    private let colorManager = IceBarColorManager()

    private(set) var currentSection: MenuBarSection.Name?

    /// Show at the mouse pointer regardless of the user's settings.
    private var hotkeyLocationOverride = false

    /// Suppresses the screen-parameters auto-hide that races with `show()`
    /// when the user clicks an inactive screen's menu bar.
    private var lastShowTimestamp: Date?

    /// Display the Thaw Bar was last shown on. Cross-screen opens must drop
    /// the previous screen's icon captures (light/dark tint is baked in).
    private var lastShownDisplayID: CGDirectDisplayID?

    private var cancellables = Set<AnyCancellable>()

    /// Background cache task started when the panel is shown.
    private var cacheTask: Task<Void, Never>?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.title = String(localized: "\(Constants.displayName) Bar")
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        // Liquid Glass: transparent window with shadow
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace, .stationary]
        self.hidesOnDeactivate = false
        self.canHide = false
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        colorManager.performSetup(with: self)
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Hide on space or screen changes. Clicking an inactive screen's menu
        // bar posts a screen change right after show(), so that one is
        // ignored.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            guard
                let self,
                let ts = self.lastShowTimestamp,
                Date().timeIntervalSince(ts) >= 1
            else {
                return
            }
            self.hide()
        }
        .store(in: &c)

        publisher(for: \.frame).map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let screen else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Updates the panel's frame origin for display on the given screen.
    private func updateOrigin(for screen: NSScreen) {
        guard let appState else {
            return
        }

        func getOrigin(for iceBarLocation: IceBarLocation) -> CGPoint {
            let menuBarHeight = screen.getMenuBarHeightEstimate()
            let defaultOriginY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

            var originForRightOfScreen: CGPoint {
                CGPoint(x: screen.frame.maxX - frame.width, y: defaultOriginY)
            }

            if hotkeyLocationOverride, let location = MouseHelpers.locationAppKit {
                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width
                let lowerBoundY = screen.frame.minY
                let upperBoundY = screen.frame.maxY - frame.height

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... (upperBoundX > lowerBoundX ? upperBoundX : lowerBoundX))
                let y = (location.y - frame.height / 2).clamped(to: lowerBoundY ... (upperBoundY > lowerBoundY ? upperBoundY : lowerBoundY))

                return CGPoint(x: x, y: y)
            }

            switch iceBarLocation {
            case .dynamic:
                if appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
                    return getOrigin(for: .mousePointer)
                }
                return getOrigin(for: .iceIcon)
            case .mousePointer:
                guard let location = MouseHelpers.locationAppKit else {
                    return getOrigin(for: .iceIcon)
                }

                let lowerBoundX = screen.frame.minX
                let upperBoundX = screen.frame.maxX - frame.width

                guard lowerBoundX <= upperBoundX else {
                    return originForRightOfScreen
                }

                let x = (location.x - frame.width / 2).clamped(to: lowerBoundX ... upperBoundX)

                return CGPoint(x: x, y: defaultOriginY)
            case .iceIcon:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard
                    lowerBound <= upperBound,
                    let controlItem = appState.itemManager.itemCache.managedItems.first(matching: .visibleControlItem),
                    // More reliable than controlItem.frame, e.g. offscreen.
                    let itemBounds = Bridging.getWindowBounds(for: controlItem.windowID)
                else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (itemBounds.midX - frame.width / 2).clamped(to: lowerBound ... upperBound), y: defaultOriginY)
            case .leftAligned:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                let x = (screen.frame.minX + 24).clamped(to: lowerBound ... upperBound)
                return CGPoint(x: x, y: defaultOriginY)
            case .rightAligned:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                let x = (screen.frame.maxX - frame.width - 24).clamped(to: lowerBound ... upperBound)
                return CGPoint(x: x, y: defaultOriginY)
            }
        }

        let location = appState.settings.displaySettings.iceBarLocation(for: screen.displayID)
        setFrameOrigin(getOrigin(for: location))
    }

    /// Shows the panel on the given screen, displaying the given
    /// menu bar section.
    func show(
        section: MenuBarSection.Name,
        on screen: NSScreen,
        triggeredByHotkey: Bool = false
    ) {
        guard let appState else {
            return
        }

        let menuBarHeight = screen.getMenuBarHeightEstimate()
        diagLog.notice("""
        show: screen=\(screen.displayID) \
        backingScaleFactor=\(Double(screen.backingScaleFactor)) \
        hasNotch=\(screen.hasNotch) \
        menuBarHeight=\(Double(menuBarHeight)) \
        frame=\(screen.frame.debugDescription) \
        visibleFrame=\(screen.visibleFrame.debugDescription)
        """)

        hotkeyLocationOverride = triggeredByHotkey && appState.settings.general.iceBarLocationOnHotkey

        // Must be set before updating the caches.
        appState.navigationState.isIceBarPresented = true
        currentSection = section
        lastShowTimestamp = Date()

        // Light/dark tint is baked into captures. Restore this display's
        // snapshot, or clear the other display's icons and recapture in the
        // background.
        let switchedDisplay = lastShownDisplayID.map { $0 != screen.displayID } ?? false
        let needsBackgroundRecapture = appState.imageCache.prepareImagesForThawBar(
            displayID: screen.displayID,
            section: section
        )
        if switchedDisplay {
            colorManager.invalidateColorInfo()
            diagLog.notice(
                "show: display \(self.lastShownDisplayID.map(String.init) ?? "nil") → \(screen.displayID); warmCache=\(!needsBackgroundRecapture)"
            )
        }
        lastShownDisplayID = screen.displayID

        // Never defer orderFront: currentSection without a visible panel
        // makes a second click call hide() instead of show().
        contentView = IceBarHostingView(
            appState: appState,
            colorManager: colorManager,
            screen: screen,
            section: section
        )

        updateOrigin(for: screen)

        // After updating the origin, before showing.
        colorManager.updateAllProperties(with: frame, screen: screen)

        orderFrontRegardless()

        let panelFrame = frame
        let targetDisplayID = screen.displayID
        cacheTask?.cancel()
        cacheTask = Task { [weak appState, weak colorManager] in
            guard let appState else { return }

            await colorManager?.refresh(with: panelFrame, screen: screen)

            await appState.itemManager.rehideTemporarilyShownItems(force: true)
            guard !Task.isCancelled else { return }

            // On a newly active screen the control items are still moving.
            // Caching now reads stale bounds, classifies everything as
            // visible, and leaves the hidden section empty.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.recaptureSection(
                section,
                preferredDisplayID: targetDisplayID
            )
        }
    }

    func hide() {
        if
            let name = currentSection,
            let section = appState?.menuBarManager.section(withName: name)
        {
            section.hide()
        }
        close()
    }

    override func close() {
        CustomTooltipPanel.shared.dismiss()
        cacheTask?.cancel()
        cacheTask = nil
        contentView = nil
        orderOut(nil)
        super.close()
        currentSection = nil
        appState?.navigationState.isIceBarPresented = false
    }

    /// Resizes the panel to match the hosting view's intrinsic content size.
    func resizeToContent() {
        guard let contentView, let screen else { return }
        let ideal = contentView.intrinsicContentSize
        guard ideal != .zero, ideal != frame.size else { return }
        setFrame(NSRect(origin: frame.origin, size: ideal), display: true, animate: false)
        updateOrigin(for: screen)
    }
}

// MARK: - IceBarHostingView

private final class IceBarHostingView: NSHostingView<IceBarContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    override func layout() {
        super.layout()
        (window as? IceBarPanel)?.resizeToContent()
    }

    init(
        appState: AppState,
        colorManager: IceBarColorManager,
        screen: NSScreen,
        section: MenuBarSection.Name
    ) {
        let rootView = IceBarContentView(
            appState: appState,
            colorManager: colorManager,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            screen: screen,
            section: section
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: IceBarContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - IceBarContentView

private struct IceBarContentView: View {
    let appState: AppState
    let colorManager: IceBarColorManager
    let itemManager: MenuBarItemManager
    let imageCache: MenuBarItemImageCache
    let menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0
    @State private var cacheGracePeriodActive = true
    @State private var loadingTimedOut = false

    let screen: NSScreen
    let section: MenuBarSection.Name

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems(for: section)
    }

    /// The menu bar's appearance unless the Thaw Bar has its own.
    private var appearance: ResolvedThawBarAppearance {
        configuration.resolvedThawBarAppearance
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
    }

    private var displaySettings: DisplaySettingsManager {
        appState.settings.displaySettings
    }

    private var layout: IceBarLayout {
        displaySettings.configuration(for: screen.displayID).iceBarLayout
    }

    private var gridColumns: Int {
        displaySettings.configuration(for: screen.displayID).gridColumns
    }

    private var itemSpacing: CGFloat {
        let offset = displaySettings.configuration(for: screen.displayID).itemSpacingOffset
        return max(0, CGFloat(offset).rounded())
    }

    private var horizontalPadding: CGFloat {
        3
    }

    private var verticalPadding: CGFloat {
        screen.hasNotch && appearance.hasRoundedShape ? 2 : 0
    }

    private var contentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        if configuration.shapeKind != .noShape, configuration.isInset, screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var itemMaxHeight: CGFloat? {
        // Raw menu bar height so icons keep native size; the clip shape trims
        // overflow.
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        return menuBarHeight > 0 ? menuBarHeight : nil
    }

    /// Mirrors `advanced.alwaysUseAppIconForMenuBarItems`.
    private var prefersAppIcon: Bool {
        appState.settings.advanced.alwaysUseAppIconForMenuBarItems
    }

    /// Per-column maximum widths for the grid layout.
    private var columnWidths: [CGFloat] {
        // Not []: the grid subscripts columnWidths whenever rows.count > 1.
        guard let maxHeight = itemMaxHeight, maxHeight > 0 else {
            return Array(repeating: 0, count: gridColumns)
        }
        let allItems = items
        let rows = allItems.chunks(ofCount: gridColumns).map(Array.init)
        return (0 ..< gridColumns).map { col in
            rows.compactMap { row in
                guard col < row.count else { return nil }
                let item = row[col]
                let cachedImage = imageCache.image(for: item.tag)
                guard !MenuBarItemIconFallback.shouldUseAppIcon(
                    for: item,
                    hasCapture: cachedImage != nil,
                    prefersAppIcon: prefersAppIcon
                ), let cachedImage else {
                    // No capture: reserve width for the square app icon.
                    return maxHeight * IceBarItemView.iconFallbackHeightRatio
                }
                let image = cachedImage.nsImage
                guard image.size.height > 0 else { return image.size.width }
                let scale = maxHeight / image.size.height
                return image.size.width * scale
            }.max() ?? 0
        }
    }

    /// Maximum content height for vertical and grid layouts so the panel
    /// does not extend below the visible screen area.
    private var maxContentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        let available = (screen.frame.maxY - menuBarHeight) - screen.visibleFrame.minY
        let totalPadding: CGFloat = 10 + verticalPadding * 2
        return max(available - totalPadding, contentHeight)
    }

    private var totalContentHeight: CGFloat {
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

    private var clipShape: some InsettableShape {
        ThawBarBorderShape.thawBarClip(
            height: contentHeight,
            hasRoundedShape: appearance.hasRoundedShape
        )
    }

    var body: some View {
        ZStack {
            Group {
                if layout == .horizontal {
                    content.frame(height: contentHeight)
                } else {
                    content.frame(height: min(totalContentHeight, maxContentHeight))
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .menuBarItemContainer(
                appState: appState,
                colorInfo: colorManager.colorInfo,
                tintOverride: MenuBarContainerTint(
                    kind: appearance.tintKind,
                    color: appearance.tintColor,
                    gradient: appearance.tintGradient,
                    opacity: appearance.tintOpacity
                )
            )
            .foregroundStyle(colorManager.colorInfo?.isBright(for: screen) == true ? .black : .white)
            .clipShape(clipShape)

            if appearance.hasBorder {
                ThawBarBorderShape.thawBarBorder(
                    height: contentHeight,
                    hasRoundedShape: appearance.hasRoundedShape,
                    borderWidth: appearance.borderWidth
                )
                .stroke(lineWidth: appearance.borderWidth)
                .foregroundStyle(Color(cgColor: appearance.borderColor))
            }
        }
        .padding(5)
        .frame(maxWidth: screen.frame.width)
        .fixedSize(horizontal: true, vertical: layout == .horizontal)
        .onAppear {
            Self.diagLog.notice("""
            IceBarContentView appeared: \
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
        .task(id: section) {
            cacheGracePeriodActive = true
            loadingTimedOut = false
            try? await Task.sleep(for: .milliseconds(600))
            cacheGracePeriodActive = false
            try? await Task.sleep(for: .seconds(2))
            loadingTimedOut = true
        }
    }

    private static let diagLog = DiagLog(category: "IceBar.Content")

    /// Opens the permissions settings pane, hiding the current section first.
    private func openPermissionsSettings() {
        menuBarManager.section(withName: section)?.hide()
        appState.navigationState.settingsNavigationIdentifier = .advanced
        appState.activate(withPolicy: .regular)
        appState.openWindow(.settings)
    }

    @ViewBuilder
    private var content: some View {
        // No Screen Recording check on purpose: uncaptured items fall back to
        // app icons, and notch overflow can force this bar on.
        if section == .alwaysHidden || section == .hidden, items.isEmpty {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                } else if !loadingTimedOut {
                    Text("No items in this section")
                } else {
                    Text("No items in this section")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: cacheGracePeriodActive) {
                Self.diagLog.debug("IceBar content: grace period changed to \(self.cacheGracePeriodActive) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onChange(of: loadingTimedOut) {
                Self.diagLog.debug("IceBar content: loading timeout changed to \(self.loadingTimedOut) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onAppear {
                Self.diagLog.debug("IceBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "No items")' for section \(self.section.logString) (grace period active: \(self.cacheGracePeriodActive))")
            }
        } else if itemManager.itemCache.managedItems.isEmpty {
            HStack {
                if loadingTimedOut {
                    Text("Unable to load menu bar items")
                    Button {
                        openPermissionsSettings()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Loading menu bar items…")
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("IceBar content: loading timeout changed to \(self.loadingTimedOut) — itemCache.managedItems is still EMPTY")
            }
            .onAppear {
                Self.diagLog.warning("IceBar content: showing 'Loading menu bar items…' — itemCache.managedItems is EMPTY. This means the item cache has never been populated.")
            }
        } else {
            let isLightBackground = colorManager.colorInfo?.isBright(for: screen) == true
            switch layout {
            case .horizontal:
                ScrollView(.horizontal) {
                    HStack(spacing: itemSpacing) {
                        ForEach(items, id: \.windowID) { item in
                            IceBarItemView(
                                imageCache: imageCache,
                                itemManager: itemManager,
                                menuBarManager: menuBarManager,
                                item: item,
                                section: section,
                                displayID: screen.displayID,
                                maxHeight: itemMaxHeight,
                                hasRoundedShape: appearance.hasRoundedShape,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground,
                                prefersAppIcon: prefersAppIcon
                            )
                        }
                    }
                    .frame(height: contentHeight)
                }
                .environment(\.isScrollEnabled, frame.width == screen.frame.width)
                .defaultScrollAnchor(.trailing)
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }

            case .vertical:
                ScrollView(.vertical) {
                    VStack(spacing: itemSpacing) {
                        ForEach(items, id: \.windowID) { item in
                            IceBarItemView(
                                imageCache: imageCache,
                                itemManager: itemManager,
                                menuBarManager: menuBarManager,
                                item: item,
                                section: section,
                                displayID: screen.displayID,
                                maxHeight: itemMaxHeight,
                                hasRoundedShape: appearance.hasRoundedShape,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground,
                                prefersAppIcon: prefersAppIcon
                            )
                        }
                    }
                }
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }

            case .grid:
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        let rows = items.chunks(ofCount: gridColumns).map(Array.init)
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, rowItems in
                            HStack(spacing: itemSpacing) {
                                ForEach(Array(rowItems.enumerated()), id: \.element.windowID) { colIndex, item in
                                    let itemView = IceBarItemView(
                                        imageCache: imageCache,
                                        itemManager: itemManager,
                                        menuBarManager: menuBarManager,
                                        item: item,
                                        section: section,
                                        displayID: screen.displayID,
                                        maxHeight: itemMaxHeight,
                                        hasRoundedShape: appearance.hasRoundedShape,
                                        tooltipDelay: appState.settings.advanced.tooltipDelay,
                                        isLightBackground: isLightBackground,
                                        prefersAppIcon: prefersAppIcon
                                    )
                                    if rows.count > 1 {
                                        itemView
                                            .frame(width: columnWidths[colIndex], alignment: .center)
                                    } else {
                                        itemView
                                    }
                                }
                                // Only pad the last row when there are multiple rows,
                                // so partial rows align with the columns above.
                                if rows.count > 1, rowIndex == rows.count - 1, rowItems.count < gridColumns {
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
                .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
                .task {
                    scrollIndicatorsFlashTrigger += 1
                }
            }
        }
    }
}

// MARK: - IceBarItemView

private struct IceBarItemView: View {
    private static let diagLog = DiagLog(category: "IceBar.ItemView")

    let imageCache: MenuBarItemImageCache
    let itemManager: MenuBarItemManager
    let menuBarManager: MenuBarManager

    @State private var isHovered = false

    let item: MenuBarItem
    let section: MenuBarSection.Name
    let displayID: CGDirectDisplayID
    let maxHeight: CGFloat?
    let hasRoundedShape: Bool
    let tooltipDelay: TimeInterval
    let isLightBackground: Bool
    /// Threaded in so the view re-renders when it is toggled.
    let prefersAppIcon: Bool

    private var pillCornerRadius: CGFloat {
        guard let h = maxHeight, h > 0 else { return 4 }
        return hasRoundedShape ? h / 2 : h / 4
    }

    private var leftClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let clickStartTime = Date.now
            IceBarItemView.diagLog.debug("leftClick: user clicked \(item.logString)")
            let panel = menuBarManager.iceBarPanel
            menuBarManager.section(withName: section)?.hide()
            Task {
                // Wait for the panel to close before checking visibility.
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                if let liveItem = await liveOnScreenItem(matching: item, on: displayID) {
                    do {
                        try await itemManager.click(item: liveItem, with: .left)
                        let duration = Date.now.timeIntervalSince(clickStartTime)
                        IceBarItemView.diagLog.debug("leftClick: ✓ completed in \(Int(duration * 1000))ms (on-screen path)")
                    } catch {
                        IceBarItemView.diagLog.error("leftClick: failed for \(item.logString): \(error)")
                    }
                } else {
                    // temporarilyShow owns the click and its fallback so
                    // shownInterfaceWindow is always captured.
                    let result = await itemManager.temporarilyShow(item: item, clickingWith: .left, on: displayID, fastPath: true)
                    let duration = Date.now.timeIntervalSince(clickStartTime)
                    IceBarItemView.diagLog.debug("leftClick: completed in \(Int(duration * 1000))ms (temp-show path, result=\(result))")
                }
            }
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let panel = menuBarManager.iceBarPanel
            menuBarManager.section(withName: section)?.hide()
            Task {
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                if let liveItem = await liveOnScreenItem(matching: item, on: displayID) {
                    do {
                        try await itemManager.click(item: liveItem, with: .right)
                    } catch {
                        IceBarItemView.diagLog.error("rightClick: failed for \(item.logString): \(error)")
                    }
                } else {
                    let result = await itemManager.temporarilyShow(item: item, clickingWith: .right, on: displayID, fastPath: true)
                    IceBarItemView.diagLog.debug("rightClick: temp-show result=\(result)")
                }
            }
        }
    }

    /// Re-fetches on-screen items and returns the live `MenuBarItem` whose
    /// tag+PID matches `item`, or `nil` if the item is not currently on-screen.
    ///
    /// Matches by tag+PID because CGWindowIDs get recycled after a long sleep.
    private func liveOnScreenItem(matching item: MenuBarItem, on displayID: CGDirectDisplayID) async -> MenuBarItem? {
        let liveItems = await MenuBarItem.getMenuBarItems(on: displayID, option: .onScreen)
        guard let liveItem = liveItems.first(matchingTag: item.tag, pid: item.sourcePID ?? item.ownerPID) else { return nil }
        return Bridging.isWindowOnScreen(liveItem.windowID) ? liveItem : nil
    }

    /// How much of the bar's height an app icon fills. A square icon at full
    /// height looks oversized next to captures.
    static let iconFallbackHeightRatio: CGFloat = 0.82

    private func targetSize(for image: NSImage, usesAppIcon: Bool) -> CGSize {
        let intrinsic = image.size
        guard intrinsic.height > 0 else {
            return intrinsic
        }

        guard let maxHeight, maxHeight > 0 else {
            return intrinsic
        }

        if usesAppIcon {
            // An app icon's intrinsic size is meaningless, unlike a capture's.
            let side = maxHeight * Self.iconFallbackHeightRatio
            return CGSize(width: side, height: side)
        }

        // Scale both ways: captures can be oversized across mixed scale
        // factors, or undersized under a notch menu bar.
        let scale = maxHeight / intrinsic.height
        return CGSize(width: intrinsic.width * scale, height: maxHeight)
    }

    var body: some View {
        let capturedImage = imageCache.image(for: item.tag)
        let usesAppIcon = MenuBarItemIconFallback.shouldUseAppIcon(
            for: item,
            hasCapture: capturedImage != nil,
            prefersAppIcon: prefersAppIcon
        )
        let image = usesAppIcon
            ? MenuBarItemIconFallback.image(for: item)
            : capturedImage?.nsImage
        if let image {
            let size = targetSize(for: image, usesAppIcon: usesAppIcon)
            Image(nsImage: image)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .frame(width: size.width, height: size.height)
                .background {
                    RoundedRectangle(cornerRadius: pillCornerRadius, style: hasRoundedShape ? .circular : .continuous)
                        .fill((isLightBackground ? Color.black : Color.white).opacity(isHovered ? 0.15 : 0))
                        .padding(.vertical, 3)
                }
                .contentShape(Rectangle())
                .overlay {
                    IceBarItemClickView(
                        item: item,
                        tooltipDelay: tooltipDelay,
                        leftClickAction: leftClickAction,
                        rightClickAction: rightClickAction,
                        onHover: { hovering in
                            isHovered = hovering
                        }
                    )
                }
                .animation(.easeInOut(duration: 0.15), value: isHovered)
                .accessibilityLabel(item.displayName)
                .accessibilityAction(named: "left click", leftClickAction)
                .accessibilityAction(named: "right click", rightClickAction)
        }
    }
}

// MARK: - IceBarItemClickView

private struct IceBarItemClickView: NSViewRepresentable {
    final class Represented: NSView {
        var item: MenuBarItem
        var tooltipDelay: TimeInterval

        var leftClickAction: () -> Void
        var rightClickAction: () -> Void
        var onHover: (Bool) -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now

        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        private lazy var tooltipController = CustomTooltipController(text: item.displayName, view: self)
        private var tooltipTrackingArea: NSTrackingArea?

        init(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            super.init(frame: .zero)
        }

        func update(
            item: MenuBarItem,
            tooltipDelay: TimeInterval,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void,
            onHover: @escaping (Bool) -> Void
        ) {
            self.item = item
            self.tooltipDelay = tooltipDelay
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.onHover = onHover
            tooltipController.text = item.displayName
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tooltipTrackingArea {
                removeTrackingArea(tooltipTrackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tooltipTrackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            tooltipController.scheduleShow(delay: tooltipDelay)
            onHover(true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            tooltipController.cancel()
            onHover(false)
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            tooltipController.cancel()
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
            tooltipController.cancel()
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                lastLeftMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                lastRightMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }
    }

    let item: MenuBarItem
    let tooltipDelay: TimeInterval

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void
    let onHover: (Bool) -> Void

    func makeNSView(context _: Context) -> Represented {
        Represented(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }

    func updateNSView(_ nsView: Represented, context _: Context) {
        // Tooltips and click handlers can change after creation.
        nsView.update(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }
}
