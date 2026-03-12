//
//  IceBar.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import SwiftUI

// MARK: - IceBarPanel

final class IceBarPanel: NSPanel {
    private let diagLog = DiagLog(category: "IceBarPanel")
    /// The shared app state.
    private weak var appState: AppState?

    /// Manager for the Ice Bar's color.
    private let colorManager = IceBarColorManager()

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// A Boolean value that indicates whether to show the panel at
    /// the mouse pointer's location, regardless of the user's
    /// settings.
    private var hotkeyLocationOverride = false

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Background cache task started when the panel is shown.
    private var cacheTask: Task<Void, Never>?

    /// Creates a new Ice Bar panel.
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
        self.backgroundColor = .clear
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
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.hide()
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
            let menuBarHeight = screen.getMenuBarHeight() ?? 0
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

        hotkeyLocationOverride = triggeredByHotkey && appState.settings.general.iceBarLocationOnHotkey

        // IMPORTANT: We must set the navigation state and current section
        // before updating the caches.
        appState.navigationState.isIceBarPresented = true
        currentSection = section

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
}

// MARK: - IceBarHostingView

private final class IceBarHostingView: NSHostingView<IceBarContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
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
    @ObservedObject var appState: AppState
    @ObservedObject var colorManager: IceBarColorManager
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var menuBarManager: MenuBarManager
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

    private var horizontalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 3
        }
        return configuration.hasRoundedShape ? 7 : 5
    }

    private var verticalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return screen.hasNotch && configuration.hasRoundedShape ? 2 : 0
        }
        return screen.hasNotch ? 0 : 2
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

    private var clipShape: some InsettableShape {
        if configuration.hasRoundedShape {
            RoundedRectangle(cornerRadius: frame.height / 2, style: .circular)
        } else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: frame.height / 4, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: frame.height / 5, style: .continuous)
        }
    }

    var body: some View {
        ZStack {
            content
                .frame(height: contentHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .menuBarItemContainer(appState: appState, colorInfo: colorManager.colorInfo)
                .foregroundStyle(colorManager.colorInfo?.color.brightness ?? 0 > 0.67 ? .black : .white)
                .clipShape(clipShape)

            if configuration.current.hasBorder {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
            }
        }
        .padding(5)
        .frame(maxWidth: screen.frame.width)
        .fixedSize()
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
        if !ScreenCapture.cachedCheckPermissions() {
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
                Self.diagLog.warning("IceBar content: showing 'requires screen recording permissions' — cachedCheckPermissions() returned false")
            }
        } else if (section == .alwaysHidden || section == .hidden) && items.isEmpty {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                    ProgressView()
                        .controlSize(.small)
                } else if !loadingTimedOut {
                    Text("No items in this section")
                    ProgressView()
                        .controlSize(.small)
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
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("IceBar content: loading timeout changed to \(self.loadingTimedOut) — itemCache.managedItems is still EMPTY")
            }
            .onAppear {
                Self.diagLog.warning("IceBar content: showing 'Loading menu bar items…' — itemCache.managedItems is EMPTY. This means the item cache has never been populated.")
            }
        } else if imageCache.cacheFailed(for: section) {
            HStack {
                if cacheGracePeriodActive {
                    Text("Loading menu bar items…")
                    ProgressView()
                        .controlSize(.small)
                } else if loadingTimedOut {
                    // Final state: no further automatic retry.
                    Text("Unable to display menu bar items")
                    Button {
                        openPermissionsSettings()
                    } label: {
                        Text("Check permissions")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                } else {
                    Text("Unable to display menu bar items")
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .onChange(of: loadingTimedOut) {
                Self.diagLog.warning("IceBar content: cacheFailed timeout changed to \(self.loadingTimedOut) for section \(self.section.logString)")
            }
            .onAppear {
                Self.diagLog.warning("IceBar content: showing '\(self.cacheGracePeriodActive ? "Loading…" : "Unable to display")' for section \(self.section.logString) — imageCache.cacheFailed=true (grace period active: \(self.cacheGracePeriodActive), loadingTimedOut: \(self.loadingTimedOut), cached images count: \(self.imageCache.images.count), items in section: \(self.itemManager.itemCache[self.section].count))")
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    let isLightBackground = (colorManager.colorInfo?.color.brightness ?? 0) > 0.67
                    ForEach(items, id: \.windowID) { item in
                        IceBarItemView(
                            imageCache: imageCache,
                            itemManager: itemManager,
                            menuBarManager: menuBarManager,
                            item: item,
                            section: section,
                            displayID: screen.displayID,
                            maxHeight: itemMaxHeight,
                            tooltipDelay: appState.settings.advanced.tooltipDelay,
                            isLightBackground: isLightBackground
                        )
                    }
                }
            }
            .environment(\.isScrollEnabled, frame.width == screen.frame.width)
            .defaultScrollAnchor(.trailing)
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

    @ObservedObject var imageCache: MenuBarItemImageCache
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var menuBarManager: MenuBarManager

    @State private var isHovered = false

    let item: MenuBarItem
    let section: MenuBarSection.Name
    let displayID: CGDirectDisplayID
    let maxHeight: CGFloat?
    let tooltipDelay: TimeInterval
    let isLightBackground: Bool

    private var leftClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let clickStartTime = Date.now
            IceBarItemView.diagLog.debug("leftClick: user clicked \(item.logString)")
            menuBarManager.section(withName: section)?.hide()
            Task {
                try await Task.sleep(for: .milliseconds(25))
                if Bridging.isWindowOnScreen(item.windowID) {
                    try await itemManager.click(item: item, with: .left)
                    let duration = Date.now.timeIntervalSince(clickStartTime)
                    IceBarItemView.diagLog.debug("leftClick: ✓ completed in \(Int(duration * 1000))ms (on-screen path)")
                } else {
                    await itemManager.temporarilyShow(item: item, clickingWith: .left, on: displayID)
                    let duration = Date.now.timeIntervalSince(clickStartTime)
                    IceBarItemView.diagLog.debug("leftClick: ✓ completed in \(Int(duration * 1000))ms (temp-show path)")
                }
            }
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            menuBarManager.section(withName: section)?.hide()
            Task {
                try await Task.sleep(for: .milliseconds(25))
                if Bridging.isWindowOnScreen(item.windowID) {
                    try await itemManager.click(item: item, with: .right)
                } else {
                    await itemManager.temporarilyShow(item: item, clickingWith: .right, on: displayID)
                }
            }
        }
    }

    private var image: NSImage? {
        guard let cachedImage = imageCache.images[item.tag] else {
            return nil
        }
        return cachedImage.nsImage
    }

    private func targetSize(for image: NSImage) -> CGSize {
        let intrinsic = image.size
        guard intrinsic.height > 0 else {
            return intrinsic
        }

        guard let maxHeight, maxHeight > 0 else {
            return intrinsic
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
                .padding(.horizontal, 3)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill((isLightBackground ? Color.black : Color.white).opacity(isHovered ? 0.1 : 0))
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
    private final class Represented: NSView {
        let item: MenuBarItem
        let tooltipDelay: TimeInterval

        let leftClickAction: () -> Void
        let rightClickAction: () -> Void
        let onHover: (Bool) -> Void

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

    func makeNSView(context _: Context) -> NSView {
        Represented(
            item: item,
            tooltipDelay: tooltipDelay,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            onHover: onHover
        )
    }

    func updateNSView(_: NSView, context _: Context) {}
}
