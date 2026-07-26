//
//  IceBar.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import SwiftUI
import ThawCapture

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

    /// Spike flag for plan 025 — see ``Defaults/Key/debugOverlayFlushMode``.
    ///
    /// Read live rather than cached so it can be toggled with `defaults write`
    /// and observed on the next show, without relaunching Thaw.
    static var isFlushOverlayMode: Bool {
        UserDefaults.standard.bool(forKey: Defaults.Key.debugOverlayFlushMode.rawValue)
    }

    /// Spike flag for plan 031 overflow rescue — see
    /// ``Defaults/Key/debugOverlayParkedMode``. Parks the bar as an
    /// *interactive* flush panel in the dead strip beside the notch: items
    /// there are assertion-hidden from the real bar but painted and clickable
    /// here, in space macOS refuses to lay items into.
    static var isParkedOverlayMode: Bool {
        UserDefaults.standard.bool(forKey: Defaults.Key.debugOverlayParkedMode.rawValue)
    }

    /// Whether either overlay spike wants menu-bar-native chrome (square
    /// corners, no shadow, no padding, true-geometry layout).
    static var isFlushChromeActive: Bool {
        isFlushOverlayMode || isParkedOverlayMode
    }

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

        // Parked mode (plan 031 overflow-rescue spike): sit on the strip with
        // the panel's right edge against the notch's left edge — the dead
        // space macOS refuses to lay items into. `debugSimulateNotch` provides
        // a synthetic 120 pt notch on displays without one. Interactive, so
        // it must land where no real item ever sits.
        if Self.isParkedOverlayMode {
            let menuBarHeight = screen.getMenuBarHeightEstimate()
            let anchorMaxX = screen.frameOfNotch?.minX ?? (screen.frame.midX - 60)
            let x = (anchorMaxX - frame.width)
                .clamped(to: screen.frame.minX ... max(screen.frame.minX, screen.frame.maxX - frame.width))
            setFrameOrigin(CGPoint(x: x, y: screen.frame.maxY - menuBarHeight))
            return
        }

        // Flush overlay mode ignores the configured location entirely: the
        // point is to sit *on* the menu bar strip, not below it. Every branch
        // above anchors to `defaultOriginY`, which is deliberately one menu bar
        // height lower.
        if Self.isFlushOverlayMode {
            let menuBarHeight = screen.getMenuBarHeightEstimate()
            // Anchor the panel's right edge to the visible section's left
            // edge: revealed hidden items live between the Thaw control item
            // and the visible items, not against the screen edge (maintainer
            // observation, 2026-07-26). Screen-edge anchoring is only the
            // fallback when no visible item is on screen to measure.
            let visibleMinX = appState.itemManager.itemCache.managedItems(for: .visible)
                .filter {
                    $0.isOnScreen && $0.bounds.width > 0
                        && $0.bounds.minX >= screen.frame.minX && $0.bounds.maxX <= screen.frame.maxX
                }
                .map(\.bounds.minX)
                .min()
            let anchorMaxX = visibleMinX ?? screen.frame.maxX
            let x = (anchorMaxX - frame.width)
                .clamped(to: screen.frame.minX ... max(screen.frame.minX, screen.frame.maxX - frame.width))
            setFrameOrigin(CGPoint(x: x, y: screen.frame.maxY - menuBarHeight))
            return
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

        // Applied per-show rather than in `init` so the spike flags can be
        // flipped with `defaults write` and evaluated without relaunching.
        // A drop shadow gives the overlay away instantly, so it goes in both
        // spike modes. Mouse handling differs: the flush mask passes clicks
        // through to the real bar, while parked mode IS the interaction
        // surface — its items are assertion-hidden and clickable only here.
        let flush = Self.isFlushChromeActive
        hasShadow = !flush
        ignoresMouseEvents = Self.isFlushOverlayMode && !Self.isParkedOverlayMode
        if Self.isParkedOverlayMode {
            diagLog.notice("show: parked overlay mode active (plan 031 overflow-rescue spike)")
        } else if flush {
            diagLog.notice("show: flush overlay mode active (plan 025 spike)")
        }

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
        cacheTask = Task { [weak appState, weak self] in
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
            // Per-item prewarming elsewhere keeps the cache warm for concealed
            // sections; additionally prewarm here on open so the bar never
            // shows blank slots for items whose glyph hasn't been captured yet.
            if #available(macOS 27, *) {
                if let section = await MainActor.run(body: { self?.currentSection }) {
                    await appState.imageCache.prewarmConcealedImagesMacOS27(sections: [section])
                }
                guard !Task.isCancelled else { return }
            }
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
        let closingSection = currentSection
        CustomTooltipPanel.shared.dismiss()
        cacheTask?.cancel()
        cacheTask = nil
        contentView = nil
        orderOut(nil)
        super.close()
        currentSection = nil
        appState?.navigationState.isIceBarPresented = false
        resetSectionStateAfterClose(closingSection)
    }

    private func resetSectionStateAfterClose(_ closingSection: MenuBarSection.Name?) {
        guard closingSection != nil, let menuBarManager = appState?.menuBarManager else {
            return
        }

        menuBarManager.showOnHoverAllowed = true
        for section in menuBarManager.sections {
            section.desiredState = .hideSection
            section.updateControlItemState(for: nil)
        }
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
            visibleControlItem: appState.menuBarManager.section(withName: .visible)?.controlItem,
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

/// The factor to render a captured menu-bar glyph at inside the Thaw Bar: scale
/// down to fit the row height, but never up. Upscaling a raster blurs, which
/// macOS 27's tight AX item bounds (shorter than the menu-bar row) made visible.
private func thawBarGlyphScale(imageHeight: CGFloat, rowHeight: CGFloat) -> CGFloat {
    guard imageHeight > 0 else { return 1 }
    return min(1, rowHeight / imageHeight)
}

private struct IceBarContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var appState: AppState
    @ObservedObject var colorManager: IceBarColorManager
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0
    @State private var cacheGracePeriodActive = true
    @State private var loadingTimedOut = false
    @State private var visibleControlItemState: ControlItem.HidingState

    let visibleControlItem: ControlItem?
    let screen: NSScreen
    let section: MenuBarSection.Name

    init(
        appState: AppState,
        colorManager: IceBarColorManager,
        itemManager: MenuBarItemManager,
        imageCache: MenuBarItemImageCache,
        menuBarManager: MenuBarManager,
        visibleControlItem: ControlItem?,
        screen: NSScreen,
        section: MenuBarSection.Name
    ) {
        self.appState = appState
        self.colorManager = colorManager
        self.itemManager = itemManager
        self.imageCache = imageCache
        self.menuBarManager = menuBarManager
        self.visibleControlItem = visibleControlItem
        self.screen = screen
        self.section = section
        self._visibleControlItemState = State(initialValue: visibleControlItem?.state ?? .hideSection)
    }

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems(for: section)
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
        IceBarPanel.isFlushChromeActive ? 0 : 3
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
        guard let maxHeight = itemMaxHeight, maxHeight > 0 else { return [] }
        let allItems = items
        let rows = stride(from: 0, to: allItems.count, by: gridColumns).map { start in
            Array(allItems[start ..< Swift.min(start + gridColumns, allItems.count)])
        }
        return (0 ..< gridColumns).map { col in
            rows.compactMap { row in
                guard col < row.count else { return nil }
                guard let image = image(for: row[col]) else { return nil }
                guard image.size.height > 0 else { return image.size.width }
                let scale = thawBarGlyphScale(imageHeight: image.size.height, rowHeight: maxHeight)
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
        if IceBarPanel.isFlushChromeActive {
            // Square corners: the menu bar has none, and a rounded edge is the
            // single most obvious tell that this is a panel.
            RoundedRectangle(cornerRadius: 0, style: .continuous)
        } else if configuration.hasRoundedShape {
            RoundedRectangle(cornerRadius: contentHeight / 2, style: .circular)
        } else {
            RoundedRectangle(cornerRadius: contentHeight / 4, style: .continuous)
        }
    }

    /// Plan 031 step 3: geometry-faithful layout for the flush overlay.
    ///
    /// The real menu bar packs items edge to edge — each item's captured crop
    /// already spans its full window bounds, native horizontal padding
    /// included — so faithful geometry is the crops at native width with zero
    /// added spacing, in section order. Width preference: live capture, then
    /// the persisted index (the transition case, where the item is concealed
    /// and cannot be measured), then the item's last known bounds.
    private func flushItemWidth(for item: MenuBarItem) -> CGFloat {
        if let captured = imageCache.image(for: item.tag) {
            return captured.scaledSize.width
        }
        if let indexed = imageCache.volatilityIndex.indexedWidth(for: item.tag) {
            return indexed
        }
        let boundsWidth = item.bounds.width
        return boundsWidth > 0 && boundsWidth < 500 ? boundsWidth : 30
    }

    /// Inter-item gap and trailing inset, measured from the live on-screen
    /// visible-section items rather than assumed. Screenshot comparison
    /// (2026-07-26) showed zero spacing packs the overlay noticeably denser
    /// than the real bar, and a flush right edge clips the last item — the
    /// real bar keeps a trailing margin. Measuring at show time tracks
    /// whatever the current OS actually does; the fallbacks only apply when
    /// no visible items are on screen to measure.
    private var flushMetrics: (gap: CGFloat, rightInset: CGFloat) {
        let visible = itemManager.itemCache.managedItems(for: .visible)
            .filter { $0.isOnScreen && $0.bounds.width > 0 && $0.bounds.minX >= screen.frame.minX }
            .sorted { $0.bounds.minX < $1.bounds.minX }

        var gaps: [CGFloat] = []
        for (left, right) in zip(visible, visible.dropFirst()) {
            let gap = right.bounds.minX - left.bounds.maxX
            if gap >= 0, gap < 40 {
                gaps.append(gap)
            }
        }
        let gap = gaps.isEmpty ? 8 : gaps.sorted()[gaps.count / 2]

        // The panel's right edge sits against the visible section's left edge
        // (see `updateOrigin`), so the trailing inset is one standard gap —
        // the space the real bar keeps between the last hidden item and the
        // first visible one — not a screen-edge margin.
        return (gap, gap)
    }

    private var flushGeometryContent: some View {
        let metrics = flushMetrics
        return HStack(spacing: metrics.gap) {
            ForEach(items, id: \.uniqueIdentifier) { item in
                IceBarItemView(
                    itemManager: itemManager,
                    menuBarManager: menuBarManager,
                    item: item,
                    section: section,
                    displayID: screen.displayID,
                    maxHeight: itemMaxHeight,
                    tooltipDelay: appState.settings.advanced.tooltipDelay,
                    displayImage: image(for: item)
                )
                .frame(width: flushItemWidth(for: item), height: contentHeight)
            }
        }
        .padding(.trailing, metrics.rightInset)
        .frame(height: contentHeight)
    }

    private func image(for item: MenuBarItem) -> NSImage? {
        let isNativeOverflowActive = appState.menuBarManager.sectionController?
            .isNativeOverflowActive(on: screen.displayID) == true
        return OverflowFallbackIcon.resolvedImage(
            for: item,
            section: section,
            appState: appState,
            cachedImage: imageCache.image(for: item.tag)?.nsImage,
            visibleControlItemState: visibleControlItemState,
            isNativeOverflowActive: isNativeOverflowActive
        )
    }

    /// Concealed sections can still render from app icons when captures fail.
    private var canShowItemsWithoutCaptures: Bool {
        OverflowFallbackIcon.supportsMissingCaptureFallback(for: section)
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

            if configuration.current.hasBorder, !IceBarPanel.isFlushChromeActive {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
            }
        }
        // The 5pt inset is what makes this read as a floating bar. Flush mode
        // must reach the screen edge and the strip's full height instead.
        .padding(IceBarPanel.isFlushChromeActive ? 0 : 5)
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
        if !ScreenCapture.hasCachedScreenRecordingPermission {
            HStack {
                Text("The \(Constants.displayName) Bar requires screen recording permissions.")

                Button {
                    openPermissionsSettings()
                } label: {
                    Text("Open \(Constants.displayName) Settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .padding(.horizontal, 10)
            .onAppear {
                Self.diagLog.warning("IceBar content: showing 'requires screen recording permissions' — hasCachedScreenRecordingPermission returned false")
            }
        } else if section == .alwaysHidden || section == .hidden, items.isEmpty {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                        .transition(.opacity)
                } else {
                    Text("No items in this section")
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: cacheGracePeriodActive)
            .padding(.horizontal, 10)
            .onChange(of: cacheGracePeriodActive) {
                Self.diagLog.debug("IceBar content: grace period changed to \(self.cacheGracePeriodActive) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onChange(of: loadingTimedOut) {
                // loadingTimedOut has no effect on the message shown here (there
                // genuinely are no items, not a stalled load) — kept only for this
                // diagnostic log.
                Self.diagLog.debug("IceBar content: loading timeout changed to \(self.loadingTimedOut) for section \(self.section.logString) — items still empty: \(self.items.isEmpty)")
            }
            .onAppear {
                Self.diagLog.debug("IceBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "No items")' for section \(self.section.logString) (grace period active: \(self.cacheGracePeriodActive))")
            }
        } else if itemManager.itemCache.managedItems.isEmpty {
            HStack {
                if loadingTimedOut {
                    Text("Unable to load menu bar items")
                        .transition(.opacity)
                    Button {
                        openPermissionsSettings()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Loading menu bar items…")
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: loadingTimedOut)
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("IceBar content: loading timeout changed to \(self.loadingTimedOut) — itemCache.managedItems is still EMPTY")
            }
            .onAppear {
                Self.diagLog.warning("IceBar content: showing 'Loading menu bar items…' — itemCache.managedItems is EMPTY. This means the item cache has never been populated.")
            }
        } else if imageCache.cacheFailed(for: section), !canShowItemsWithoutCaptures {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                        .transition(.opacity)
                } else if loadingTimedOut {
                    // Final state: no further automatic retry.
                    Text("Unable to display menu bar items")
                        .transition(.opacity)
                    Button {
                        openPermissionsSettings()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Loading menu bar items…")
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: cacheGracePeriodActive)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: loadingTimedOut)
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("IceBar content: cacheFailed timeout changed to \(self.loadingTimedOut) for section \(self.section.logString)")
            }
            .onAppear {
                Self.diagLog.warning("IceBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "Unable to display")' for section \(self.section.logString) — imageCache.cacheFailed=true (grace period active: \(self.cacheGracePeriodActive), loadingTimedOut: \(self.loadingTimedOut), cached images count: \(self.imageCache.images.count), items in section: \(self.itemManager.itemCache[self.section].count))")
            }
        } else if IceBarPanel.isFlushChromeActive {
            flushGeometryContent
        } else {
            Group {
                switch layout {
                case .horizontal:
                    ScrollView(.horizontal) {
                        HStack(spacing: itemSpacing) {
                            ForEach(items, id: \.uniqueIdentifier) { item in
                                IceBarItemView(
                                    itemManager: itemManager,
                                    menuBarManager: menuBarManager,
                                    item: item,
                                    section: section,
                                    displayID: screen.displayID,
                                    maxHeight: itemMaxHeight,
                                    tooltipDelay: appState.settings.advanced.tooltipDelay,
                                    displayImage: image(for: item)
                                )
                            }
                        }
                        .frame(height: contentHeight)
                    }
                    .environment(\.isScrollEnabled, frame.width == screen.frame.width)
                    .defaultScrollAnchor(.trailing)

                case .vertical:
                    ScrollView(.vertical) {
                        VStack(spacing: itemSpacing) {
                            ForEach(items, id: \.uniqueIdentifier) { item in
                                IceBarItemView(
                                    itemManager: itemManager,
                                    menuBarManager: menuBarManager,
                                    item: item,
                                    section: section,
                                    displayID: screen.displayID,
                                    maxHeight: itemMaxHeight,
                                    tooltipDelay: appState.settings.advanced.tooltipDelay,
                                    displayImage: image(for: item)
                                )
                            }
                        }
                    }

                case .grid:
                    let columnWidths = self.columnWidths
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            let rows = stride(from: 0, to: items.count, by: gridColumns).map { start in
                                Array(items[start ..< Swift.min(start + gridColumns, items.count)])
                            }
                            ForEach(rows.indices, id: \.self) { rowIndex in
                                let rowItems = rows[rowIndex]
                                HStack(spacing: itemSpacing) {
                                    ForEach(Array(rowItems.enumerated()), id: \.element.uniqueIdentifier) { colIndex, item in
                                        let itemView = IceBarItemView(
                                            itemManager: itemManager,
                                            menuBarManager: menuBarManager,
                                            item: item,
                                            section: section,
                                            displayID: screen.displayID,
                                            maxHeight: itemMaxHeight,
                                            tooltipDelay: appState.settings.advanced.tooltipDelay,
                                            displayImage: image(for: item)
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
                }
            }
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }
}

// MARK: - IceBarItemView

private struct IceBarItemView: View {
    private static let diagLog = DiagLog(category: "IceBar.ItemView")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var menuBarManager: MenuBarManager

    let item: MenuBarItem
    let section: MenuBarSection.Name
    let displayID: CGDirectDisplayID
    let maxHeight: CGFloat?
    let tooltipDelay: TimeInterval
    let displayImage: NSImage?

    @State private var isHovered = false

    private var leftClickAction: () -> Void {
        clickAction(with: .left)
    }

    private var rightClickAction: () -> Void {
        clickAction(with: .right)
    }

    private func clickAction(with button: CGMouseButton) -> () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let clickStartTime = Date.now
            IceBarItemView.diagLog.debug("click(\(button == .left ? "left" : "right")): user clicked \(item.logString)")
            let panel = menuBarManager.iceBarPanel
            menuBarManager.section(withName: section)?.hide()
            Task {
                // Wait until the IceBar panel is fully closed before checking
                // item visibility. Uses KVO on isVisible so we resume as soon
                // as the panel hides rather than busy-polling.
                await panel.waitUntilClosed(timeout: .milliseconds(200))
                if #available(macOS 27, *) {
                    await itemManager.clickConcealedItem(item: item, with: button, on: displayID)
                    let duration = Date.now.timeIntervalSince(clickStartTime)
                    IceBarItemView.diagLog.debug("click(\(button == .left ? "left" : "right")): completed in \(Int(duration * 1000))ms (macOS 27 concealed-item path)")
                } else if let liveItem = await liveOnScreenItem(matching: item, on: displayID) {
                    do {
                        try await itemManager.click(item: liveItem, with: button)
                        let duration = Date.now.timeIntervalSince(clickStartTime)
                        IceBarItemView.diagLog.debug("click(\(button == .left ? "left" : "right")): ✓ completed in \(Int(duration * 1000))ms (on-screen path)")
                    } catch {
                        IceBarItemView.diagLog.error("click(\(button == .left ? "left" : "right")): click failed: \(error)")
                    }
                } else {
                    // temporarilyShow handles move, click, and fallback click
                    // internally so that shownInterfaceWindow is always captured
                    // regardless of which click attempt succeeds.
                    let result = await itemManager.temporarilyShow(item: item, clickingWith: button, on: displayID, fastPath: true)
                    let duration = Date.now.timeIntervalSince(clickStartTime)
                    IceBarItemView.diagLog.debug("click(\(button == .left ? "left" : "right")): completed in \(Int(duration * 1000))ms (temp-show path, result=\(result))")
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
        guard let liveItem = liveItems.first(where: { $0.hasSameIdentity(as: item) }) else {
            return nil
        }
        return Bridging.isWindowOnScreen(liveItem.windowID) ? liveItem : nil
    }

    private func targetSize(for image: NSImage) -> CGSize {
        let intrinsic = image.size
        guard intrinsic.height > 0 else {
            return intrinsic
        }

        guard let maxHeight, maxHeight > 0 else {
            return intrinsic
        }

        // Scale down to fit, never up (see `thawBarGlyphScale`): captured at
        // their native menu-bar size the icons render crisply and simply sit
        // centered in the (taller) content row.
        let scale = thawBarGlyphScale(imageHeight: intrinsic.height, rowHeight: maxHeight)
        return CGSize(width: intrinsic.width * scale, height: intrinsic.height * scale)
    }

    var body: some View {
        if let image = displayImage {
            let size = targetSize(for: image)
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .scaleEffect(isHovered ? 1.12 : 1.0)
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isHovered)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: displayImage == nil)
                .overlay {
                    IceBarItemClickView(
                        item: item,
                        tooltipDelay: tooltipDelay,
                        leftClickAction: leftClickAction,
                        rightClickAction: rightClickAction,
                        onHover: { isHovered = $0 }
                    )
                }
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
