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
    /// The shared app state.
    private weak var appState: AppState?

    /// Manager for the Thaw Bar's color.
    private let colorManager = IceBarColorManager()

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// A Boolean value that indicates whether to show the panel at
    /// the mouse pointer's location, regardless of the user's
    /// settings.
    private var hotkeyLocationOverride = false

    /// Timestamp of most recent `show()`. Used to suppress
    /// `didChangeScreenParametersNotification` auto-hide when the
    /// user clicks an inactive screen's menubar (active menu bar
    /// change posts that notification, racing with the show).
    private var lastShowTimestamp: Date?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Background cache task started when the panel is shown.
    private var cacheTask: Task<Void, Never>?

    /// Creates a new Thaw Bar panel with Liquid Glass support.
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

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        colorManager.performSetup(with: self)
    }

    /// Configures the internal observers.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Hide the panel when the active space or screen parameters change.
        // Guard against didChangeScreenParametersNotification racing with
        // show(): clicking an inactive screen's menubar activates it, which
        // posts this notification. Without the guard, the notification would
        // hide the panel immediately after show() opened it.
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

        // Update the panel's origin whenever its size changes.
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
                    // Bridging API is more reliable than controlItem.frame in some
                    // cases (like if the item is offscreen).
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

        // IMPORTANT: We must set the navigation state and current section
        // before updating the caches.
        appState.navigationState.isIceBarPresented = true
        currentSection = section
        lastShowTimestamp = Date()

        // Show the panel immediately with whatever cached data we have.
        // The SwiftUI view observes itemManager and imageCache, so it
        // will re-render automatically as the background updates land.
        contentView = IceBarHostingView(
            appState: appState,
            colorManager: colorManager,
            screen: screen,
            section: section
        )

        updateOrigin(for: screen)

        // Color manager must be updated after updating the panel's origin,
        // but before it is shown.
        //
        // Color manager handles frame changes automatically, but does so on
        // the main queue, so we need to update manually once before showing
        // the panel to prevent the color from flashing.
        colorManager.updateAllProperties(with: frame, screen: screen)

        orderFrontRegardless()

        // Rehide temporarily shown items and refresh caches in the
        // background. Ordering is preserved: rehide moves items back
        // to their correct sections before the cache is rebuilt.
        // The task is cancelled in close() to avoid holding appState.
        cacheTask?.cancel()
        cacheTask = Task { [weak appState] in
            guard let appState else { return }
            await appState.itemManager.rehideTemporarilyShownItems(force: true)
            guard !Task.isCancelled else { return }
            // Settle delay: when the IceBar just opened on a screen that
            // was previously inactive, the menu bar has moved screens and
            // NSStatusItem windows (control item chevrons) are still
            // positioning. Without this delay, cacheItemsIfNeeded can
            // recache with stale/zero control item bounds, causing
            // findSection() to misclassify all items as .visible and
            // leave the hidden section cache empty ("No items…").
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            await appState.imageCache.updateCache()
        }
    }

    /// Hides the panel.
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
        screen.hasNotch && configuration.hasRoundedShape ? 2 : 0
    }

    private var contentHeight: CGFloat {
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        if configuration.shapeKind != .noShape, configuration.isInset, screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var itemMaxHeight: CGFloat? {
        // Use the raw menu bar height so icons match their native size,
        // regardless of any inset or padding applied to the bar shape.
        // The clip shape trims any overflow.
        let menuBarHeight = screen.getMenuBarHeightEstimate()
        return menuBarHeight > 0 ? menuBarHeight : nil
    }

    /// Per-column maximum widths for the grid layout.
    private var columnWidths: [CGFloat] {
        // Zero-width placeholders (not []) during transient zero-height
        // states: the grid body subscripts columnWidths[colIndex] whenever
        // rows.count > 1, and an empty array would crash there.
        guard let maxHeight = itemMaxHeight, maxHeight > 0 else {
            return Array(repeating: 0, count: gridColumns)
        }
        let allItems = items
        let rows = allItems.chunks(ofCount: gridColumns).map(Array.init)
        return (0 ..< gridColumns).map { col in
            rows.compactMap { row in
                guard col < row.count else { return nil }
                guard let cachedImage = imageCache.images[row[col].tag] else {
                    // No capture: the item renders as a square app icon, so
                    // reserve that width rather than dropping the column and
                    // letting the grid collapse around a visible item.
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

    /// Total intrinsic height of all items/rows for the current layout.
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
        if configuration.hasRoundedShape {
            RoundedRectangle(cornerRadius: contentHeight / 2, style: .circular)
        } else {
            RoundedRectangle(cornerRadius: contentHeight / 4, style: .continuous)
        }
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
            .menuBarItemContainer(appState: appState, colorInfo: colorManager.colorInfo)
            .foregroundStyle(colorManager.colorInfo?.isBright(for: screen) == true ? .black : .white)
            .clipShape(clipShape)

            if configuration.current.borderOnThawBar {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
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
        // No Screen Recording branch here on purpose. Items without a capture
        // render as their owning app's icon, which is the whole point of the
        // fallback: the permission is documented as optional, and notch
        // overflow can force this bar on without the user ever choosing it.
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
                                hasRoundedShape: configuration.hasRoundedShape,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground
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
                                hasRoundedShape: configuration.hasRoundedShape,
                                tooltipDelay: appState.settings.advanced.tooltipDelay,
                                isLightBackground: isLightBackground
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
                                        hasRoundedShape: configuration.hasRoundedShape,
                                        tooltipDelay: appState.settings.advanced.tooltipDelay,
                                        isLightBackground: isLightBackground
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
                // Wait until the IceBar panel is fully closed before checking
                // item visibility. Uses KVO on isVisible so we resume as soon
                // as the panel hides rather than busy-polling.
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                if let liveItem = await liveOnScreenItem(matching: item, on: displayID) {
                    do {
                        try await itemManager.click(item: liveItem, with: .left)
                        let duration = Date.now.timeIntervalSince(clickStartTime)
                        IceBarItemView.diagLog.debug("leftClick: ✓ completed in \(Int(duration * 1000))ms (on-screen path)")
                    } catch {
                        // Surfacing this matters: a swallowed error here is a
                        // user click that silently does nothing.
                        IceBarItemView.diagLog.error("leftClick: failed for \(item.logString): \(error)")
                    }
                } else {
                    // temporarilyShow handles move, click, and fallback click
                    // internally so that shownInterfaceWindow is always captured
                    // regardless of which click attempt succeeds.
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
                        // Surfacing this matters: a swallowed error here is a
                        // user click that silently does nothing.
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
    /// Matching by tag+PID rather than the cached `windowID` guards against
    /// CGWindowID recycling after a long system sleep, which would otherwise
    /// cause `isWindowOnScreen` to return a false positive for an unrelated window.
    private func liveOnScreenItem(matching item: MenuBarItem, on displayID: CGDirectDisplayID) async -> MenuBarItem? {
        let liveItems = await MenuBarItem.getMenuBarItems(on: displayID, option: .onScreen)
        guard let liveItem = liveItems.first(matchingTag: item.tag, pid: item.sourcePID ?? item.ownerPID) else { return nil }
        return Bridging.isWindowOnScreen(liveItem.windowID) ? liveItem : nil
    }

    /// How much of the bar's height an app icon fills. Captures are drawn
    /// at full height because they are already menu-bar-sized artwork; a
    /// square app icon at full height reads as oversized next to them.
    static let iconFallbackHeightRatio: CGFloat = 0.82

    /// The captured glyph, or the owning app's icon when no capture is
    /// available — most often because Screen Recording was declined.
    private var image: NSImage? {
        if let cachedImage = imageCache.images[item.tag] {
            return cachedImage.nsImage
        }
        return MenuBarItemIconFallback.image(for: item)
    }

    /// Whether ``image`` is an app icon rather than a captured glyph.
    ///
    /// An icon is square and arbitrarily large, so it is sized to the bar's
    /// height instead of being scaled from its own intrinsic size the way a
    /// capture is.
    private var isIconFallback: Bool {
        imageCache.images[item.tag] == nil
    }

    private func targetSize(for image: NSImage) -> CGSize {
        let intrinsic = image.size
        guard intrinsic.height > 0 else {
            return intrinsic
        }

        guard let maxHeight, maxHeight > 0 else {
            return intrinsic
        }

        if isIconFallback {
            // App icons are square and come at whatever size AppKit felt
            // like; a capture's intrinsic size is meaningful, an icon's is
            // not. Inset slightly so icons do not crowd the bar the way
            // full-height glyphs would.
            let side = maxHeight * Self.iconFallbackHeightRatio
            return CGSize(width: side, height: side)
        }

        // Scale to fill the available height exactly. This handles both
        // directions: shrinking oversized captures (e.g. multi-monitor with
        // different scale factors) and growing undersized ones (e.g. 16"
        // MacBook Pro where the captured item height can be smaller than the
        // IceBar's content height derived from the full notch-area menu bar).
        let scale = maxHeight / intrinsic.height
        return CGSize(width: intrinsic.width * scale, height: maxHeight)
    }

    var body: some View {
        if let image {
            let size = targetSize(for: image)
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
        // Keep the backing `NSView` in sync with SwiftUI updates; tooltip text,
        // tooltip timing, and click handlers can all change after creation.
        nsView.update(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }
}
