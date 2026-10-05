//
//  ThawBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import SwiftUI
import ThawCapture
import ThawUI

// MARK: - ThawBarPanel

final class ThawBarPanel: NSPanel {
    private let diagLog = DiagLog(category: "ThawBarPanel")
    private weak var appState: AppState?

    private let colorManager = ThawBarColorManager()

    private(set) var currentSection: MenuBarSection.Name?

    enum Presentation {
        /// A section's items: the panel owns the reveal.
        case section
        /// Inline reveal owns the section and closes this companion Thaw Bar Only panel.
        case alongsideReveal
        /// Thaw Bar Only items opened from their icon or shortcut, with no section ownership.
        case thawBarOnly
        /// Folder items opened from their icon, with no section ownership.
        case folder

        var showsOnlyThawBarOnlyItems: Bool {
            self == .alongsideReveal || self == .thawBarOnly
        }
    }

    private(set) var presentation = Presentation.section

    /// Members in folder order, set only for folder presentation.
    private(set) var folderMemberIdentifiers: [String]?

    /// Opening icon bounds in cache-global coordinates; its horizontal center overrides normal placement.
    private var openingIconFrame: CGRect?

    /// Override configured placement with the pointer location.
    private var hotkeyLocationOverride = false

    /// Suppress auto-hide when activating an inactive screen posts a notification racing with show().
    private var lastShowTimestamp: Date?

    private var cancellables = Set<AnyCancellable>()

    /// Background cache task started when the panel is shown.
    private var cacheTask: Task<Void, Never>?

    /// Stop repeated failed WindowServer measurements until the control item gets a new ID.
    private var staleAnchorWindowID: CGWindowID?

    /// Observe the lock setting through Observation rather than a Combine projection.
    private var lockPositionObservationTask: Task<Void, Never>?

    /// Global monitor that dismisses the panel on an outside click while shown.
    /// Global monitors cannot consume the click, so the app still receives it.
    private var outsideClickMonitor: EventMonitor?

    /// Watch unmodified Esc only while shown; from another app, close only when the pointer is over the bar.
    private var escapeMonitor: EventMonitor?

    /// The keyboard highlight, shared with the content view.
    private let keyboardFocus = ThawBarKeyboardFocus()

    /// Take key focus only for shortcut opens; click opens preserve the front app's focus.
    private var acceptsKeyboard = false

    override var canBecomeKey: Bool {
        acceptsKeyboard
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: keyboardFocus.move(dx: -1, dy: 0)
        case 124: keyboardFocus.move(dx: 1, dy: 0)
        case 125: keyboardFocus.move(dx: 0, dy: 1)
        case 126: keyboardFocus.move(dx: 0, dy: -1)
        // Return, keypad Enter, Space.
        case 36, 76, 49: keyboardFocus.activate()
        default: super.keyDown(with: event)
        }
    }

    /// Presentation tests disable global outside-click dismissal so unrelated clicks cannot close the test panel.
    var dismissesOnOutsideClick = true

    deinit {
        lockPositionObservationTask?.cancel()
    }

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
        self.isOpaque = false
        self.hasShadow = true
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace, .stationary]
        self.hidesOnDeactivate = false
        self.canHide = false
    }

    func performSetup(with appState: AppState) {
        self.appState = appState

        // Observations delivers the current lock value before subsequent changes.
        lockPositionObservationTask?.cancel()
        lockPositionObservationTask = Task { @MainActor [weak self, generalSettings = appState.settings.general] in
            let changes = Observations { generalSettings.lockThawBarPosition }
            for await locked in changes {
                guard let self else { return }
                isMovableByWindowBackground = !locked
            }
        }

        // Activating an inactive screen posts a screen-change notification; do not let it close a just-opened bar.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            guard
                let self,
                let ts = lastShowTimestamp,
                Date().timeIntervalSince(ts) >= 1
            else {
                return
            }
            hide()
        }
        .store(in: &cancellables)

        publisher(for: \.frame).map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, let screen else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &cancellables)

        colorManager.performSetup(with: self, appState: appState)
    }

    /// Nil when the panel is wider than the screen and no placement fits.
    private func fittableXRange(on screen: NSScreen) -> ClosedRange<CGFloat>? {
        let lower = screen.frame.minX
        let upper = screen.frame.maxX - frame.width
        return lower <= upper ? lower ... upper : nil
    }

    /// The origin Y that rests the panel's top edge just under the menu bar.
    private func restingY(on screen: NSScreen) -> CGFloat {
        return (screen.frame.maxY - 1) - screen.getMenuBarHeightEstimate() - frame.height
    }

    /// Prefer Bridging bounds, which remain reliable offscreen.
    /// Window-ID churn can invalidate lookup; use cached bounds before falling back to the right edge.
    private func controlItemAnchorBounds(appState: AppState) -> CGRect? {
        guard let item = appState.itemManager.managedItems.first(matching: .visibleControlItem) else {
            diagLog.warning("ThawBar: no visible control item in the item list; cannot anchor to the icon")
            return nil
        }
        if item.windowID == staleAnchorWindowID {
            return item.bounds.isEmpty ? nil : item.bounds
        }
        if let bounds = Bridging.getWindowBounds(for: item.windowID) {
            staleAnchorWindowID = nil
            return bounds
        }
        staleAnchorWindowID = item.windowID
        if !item.bounds.isEmpty {
            diagLog.debug(
                """
                ThawBar: no window bounds for the visible control item \
                (windowID \(item.windowID)); anchoring to its last known bounds \(item.bounds) \
                until it reports a new window ID
                """
            )
            return item.bounds
        }
        diagLog.warning(
            "ThawBar: the visible control item has neither window bounds nor cached bounds (windowID \(item.windowID))"
        )
        return nil
    }

    /// Reject parked x = -1 frames, which would incorrectly anchor the bar at the left edge.
    static nonisolated func isUsableThawIconAnchor(_ anchor: CGRect, screenFrame: CGRect) -> Bool {
        anchor.height > 0
            && anchor.width > 0
            && anchor.minX > screenFrame.minX
            && anchor.maxX <= screenFrame.maxX
    }

    /// Nil when placement resolves to an icon that is switched off, sending callers to the right edge.
    /// Its movable 2-point stand-in would make the bar jump between opens.
    static nonisolated func concreteLocation(
        for location: ThawBarLocation,
        pointerInEmptyMenuBarSpace: Bool,
        hasPointerLocation: Bool,
        showsThawIcon: Bool
    ) -> ThawBarLocation? {
        var resolved = location
        if resolved == .dynamic {
            resolved = pointerInEmptyMenuBarSpace ? .mousePointer : .thawIcon
        }
        if resolved == .mousePointer, !hasPointerLocation {
            resolved = .thawIcon
        }
        if resolved == .thawIcon, !showsThawIcon {
            return nil
        }
        return resolved
    }

    /// Resolve a concrete location and clamp it on-screen; missing anchors or oversized panels use the right edge.
    private func floatingOrigin(for location: ThawBarLocation, on screen: NSScreen, appState: AppState) -> CGPoint {
        let y = restingY(on: screen)

        // Hotkey placement overrides configuration and centers on the pointer in both axes.
        if hotkeyLocationOverride, let mouse = MouseHelpers.locationAppKit {
            let x = (mouse.x - frame.width / 2).clamped(to: fittableXRange(on: screen) ?? screen.frame.minX ... screen.frame.minX)
            let maxOriginY = max(screen.frame.minY, screen.frame.maxY - frame.height)
            return CGPoint(
                x: x,
                y: (mouse.y - frame.height / 2).clamped(to: screen.frame.minY ... maxOriginY)
            )
        }

        let concrete = Self.concreteLocation(
            for: location,
            pointerInEmptyMenuBarSpace: location == .dynamic
                && appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen),
            hasPointerLocation: MouseHelpers.locationAppKit != nil,
            showsThawIcon: appState.settings.general.showThawIcon
        )

        let rightEdgeX = screen.frame.maxX - frame.width
        guard let xRange = fittableXRange(on: screen) else {
            return CGPoint(x: rightEdgeX, y: y)
        }

        // Opening icons override configured placement.
        if let openingIconFrame, (screen.frame.minX ... screen.frame.maxX).contains(openingIconFrame.midX) {
            return CGPoint(x: (openingIconFrame.midX - frame.width / 2).clamped(to: xRange), y: y)
        }

        // A disabled icon falls back silently; logging normal behavior would repeat every layout pass.
        guard let resolved = concrete else {
            return CGPoint(x: rightEdgeX, y: y)
        }

        let desiredX: CGFloat? = switch resolved {
        case .dynamic:
            // Reduced to a concrete location above.
            nil
        case .mousePointer:
            MouseHelpers.locationAppKit.map { $0.x - frame.width / 2 }
        case .thawIcon:
            controlItemAnchorBounds(appState: appState).flatMap { anchor -> CGFloat? in
                guard Self.isUsableThawIconAnchor(anchor, screenFrame: screen.frame) else {
                    diagLog.warning(
                        "ThawBar: visible control item anchor \(anchor) is off-band; " +
                            "parking at the screen's right edge"
                    )
                    return nil
                }
                return anchor.midX - frame.width / 2
            }
        case .leftAligned:
            screen.frame.minX + 24
        case .rightAligned:
            screen.frame.maxX - frame.width - 24
        }

        guard let desiredX else {
            // Log the unresolved anchor so right-edge fallback is distinguishable from an ignored setting.
            diagLog.warning(
                "ThawBar: \(resolved) did not resolve an anchor; parking at the screen's right edge"
            )
            return CGPoint(x: rightEdgeX, y: y)
        }
        let clamped = desiredX.clamped(to: xRange)
        if abs(clamped - desiredX) > 1 {
            diagLog.debug(
                "ThawBar: \(resolved) wanted x=\(desiredX) but the fittable range \(xRange) clamped it to \(clamped)"
            )
        }
        return CGPoint(x: clamped, y: y)
    }

    private func updateOrigin(for screen: NSScreen) {
        guard let appState else {
            return
        }

        let location = appState.settings.displaySettings.thawBarLocation(for: screen.displayID)
        setFrameOrigin(floatingOrigin(for: location, on: screen, appState: appState))
    }

    func show(
        section: MenuBarSection.Name,
        on screen: NSScreen,
        triggeredByHotkey: Bool = false,
        presentation: Presentation = .section,
        folderMembers: [String]? = nil,
        openedFrom iconFrame: CGRect? = nil
    ) {
        guard let appState else {
            return
        }
        self.presentation = presentation
        folderMemberIdentifiers = presentation == .folder ? folderMembers : nil
        openingIconFrame = iconFrame

        let menuBarHeight = screen.getMenuBarHeightEstimate()
        diagLog.notice("""
        show: screen=\(screen.displayID) \
        backingScaleFactor=\(Double(screen.backingScaleFactor)) \
        hasNotch=\(screen.hasNotch) \
        menuBarHeight=\(Double(menuBarHeight)) \
        frame=\(screen.frame.debugDescription) \
        visibleFrame=\(screen.visibleFrame.debugDescription)
        """)

        hotkeyLocationOverride = triggeredByHotkey && appState.settings.general.thawBarLocationOnHotkey
        // Probe once per open; the stale marker only suppresses repeated layout-pass lookups.
        staleAnchorWindowID = nil

        hasShadow = appState.appearanceManager.configuration.resolvedThawBarAppearance.hasShadow
            || appState.appearanceManager.configuration.resolvedThawBarAppearance.backgroundHasShadow

        // Set navigation state and section before updating caches.
        appState.navigationState.isThawBarPresented = true
        currentSection = section
        lastShowTimestamp = Date()

        // Show cached data immediately; Observation renders background updates as they arrive.
        if let hostingView = contentView as? ThawBarHostingView {
            hostingView.update(
                appState: appState,
                colorManager: colorManager,
                keyboardFocus: keyboardFocus,
                screen: screen,
                section: section,
                showsOnlyThawBarOnlyItems: presentation.showsOnlyThawBarOnlyItems,
                folderMembers: folderMemberIdentifiers
            )
        } else {
            contentView = ThawBarHostingView(
                appState: appState,
                colorManager: colorManager,
                keyboardFocus: keyboardFocus,
                screen: screen,
                section: section,
                showsOnlyThawBarOnlyItems: presentation.showsOnlyThawBarOnlyItems,
                folderMembers: folderMemberIdentifiers
            )
        }

        // Measure before placement: a zero-size panel at the right edge has no NSWindow.screen for later repositioning.
        resizeToContent(on: screen)

        // Update color after placement but before showing; queued frame-change updates would flash the wrong color.
        colorManager.updateAllProperties(with: frame, screen: screen)

        // Keep the frontmost app's focus; keyboard-triggered opens take key focus separately.
        orderFrontRegardless()

        // Shortcut opens highlight the first item and take key focus without activating Thaw.
        acceptsKeyboard = triggeredByHotkey
        if acceptsKeyboard {
            makeKey()
            keyboardFocus.begin()
        }

        // Nonactivating panels get no resign-key dismissal; monitor outside clicks unless inline reveal owns rehide.
        if presentation != .alongsideReveal {
            installOutsideClickMonitor()
        }

        // Non-section items are never on the bar; capturing would unnecessarily reveal and reconceal the user's section.
        guard presentation == .section else {
            cacheTask?.cancel()
            cacheTask = nil
            return
        }

        // Cancel background refresh on close to avoid retaining appState.
        cacheTask?.cancel()
        cacheTask = Task { [weak appState, weak self] in
            guard let appState else { return }
            guard !Task.isCancelled else { return }
            // Wait for control windows after screen activation; stale bounds can classify everything Visible and empty Hidden.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await appState.itemManager.cacheItemsIfNeeded()
            guard !Task.isCancelled else { return }
            // Prewarm on open as well as per-item so uncaptured glyphs do not leave blank slots.
            if let section = await MainActor.run(body: { self?.currentSection }) {
                await appState.imageCache.prewarmConcealedImages(sections: [section])
            }
            guard !Task.isCancelled else { return }
            await appState.imageCache.recaptureIfWarranted()
        }
    }

    private func installOutsideClickMonitor() {
        if escapeMonitor == nil {
            // Key code 53 is Esc on every layout.
            escapeMonitor = EventMonitor.startUniversal(
                for: .keyDown,
                localHandler: { [weak self] event in
                    guard event.keyCode == 53 else { return event }
                    MainActor.assumeIsolated { self?.hide() }
                    return nil
                },
                globalHandler: { [weak self] event in
                    guard event.keyCode == 53 else { return }
                    MainActor.assumeIsolated {
                        // Do not use another app's Esc to close the bar unless the pointer is over it.
                        guard let self, self.frame.contains(NSEvent.mouseLocation) else { return }
                        self.hide()
                    }
                }
            )
        }
        guard dismissesOnOutsideClick, outsideClickMonitor == nil else { return }
        outsideClickMonitor = EventMonitor.startGlobal(for: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // Global event monitors deliver on the main run loop; an actor hop would delay dismissal.
            MainActor.assumeIsolated {
                self?.hideIfClickIsOutside()
            }
        }
    }

    /// The live status window can move displays before the AX cache catches up.
    /// Consuming that icon's mouse-down would close the panel before its action toggles it open again.
    static nonisolated func isControlItemClick(
        appKitLocation: CGPoint,
        liveControlItemFrame: CGRect?,
        quartzLocation: CGPoint?,
        cachedControlItemFrame: CGRect?
    ) -> Bool {
        if let liveControlItemFrame, liveControlItemFrame.contains(appKitLocation) {
            return true
        }
        if let quartzLocation, let cachedControlItemFrame {
            return cachedControlItemFrame.contains(quartzLocation)
        }
        return false
    }

    /// Exclude the Thaw icon from outside-click dismissal because its click toggles the panel.
    private func hideIfClickIsOutside() {
        // Test AppKit panel and Core Graphics anchor in their own coordinate spaces or the icon never matches.
        if frame.contains(NSEvent.mouseLocation) {
            return
        }
        // With the icon off there is no icon to click, only its 2-pt stand-in.
        if let appState,
           appState.settings.general.showThawIcon,
           Self.isControlItemClick(
               appKitLocation: NSEvent.mouseLocation,
               liveControlItemFrame: appState.menuBarManager.section(withName: .visible)?.controlItem.window?.frame,
               quartzLocation: MouseHelpers.locationCoreGraphics,
               cachedControlItemFrame: controlItemAnchorBounds(appState: appState)
           )
        {
            return
        }
        // The Thaw Bar Only icon's own click toggles the panel.
        if presentation == .thawBarOnly, appState?.thawBarOnlyProxies.launcherContainsPointer() == true {
            return
        }
        if presentation == .folder, appState?.groupFolders.iconContainsPointer() == true {
            return
        }
        hide()
    }

    func closeIfShowingThawBarOnly() {
        if isVisible, presentation == .thawBarOnly {
            close()
        }
    }

    func hide() {
        if presentation == .section,
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
        outsideClickMonitor?.stop()
        outsideClickMonitor = nil
        escapeMonitor?.stop()
        escapeMonitor = nil
        acceptsKeyboard = false
        keyboardFocus.end()
        // Keep the hosting graph for the next open; show() replaces its inputs instead of rebuilding.
        currentSection = nil
        let ownedSection = presentation == .section
        presentation = .section
        appState?.navigationState.isThawBarPresented = false
        orderOut(nil)
        super.close()
        if ownedSection {
            resetSectionStateAfterClose(closingSection)
        }
        appState?.restoreAccessoryPolicyIfUnused()
        MemoryReclaimer.scheduleRelief(reason: "Thaw Bar closed")
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

    func resizeToContent(on targetScreen: NSScreen? = nil) {
        guard let contentView, let screen = targetScreen ?? screen else { return }
        let ideal = contentView.intrinsicContentSize
        guard ideal.width.isFinite, ideal.height.isFinite, ideal.width > 0, ideal.height > 0 else { return }
        guard ideal != frame.size || targetScreen != nil else { return }
        if ideal != frame.size {
            setFrame(NSRect(origin: frame.origin, size: ideal), display: true, animate: false)
        }
        // Reopening on another screen still needs placement when size is unchanged.
        updateOrigin(for: screen)
    }
}

// MARK: - ThawBarHostingView

private final class ThawBarHostingView: NSHostingView<ThawBarContentView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    override func layout() {
        super.layout()
        (window as? ThawBarPanel)?.resizeToContent()
    }

    init(
        appState: AppState,
        colorManager: ThawBarColorManager,
        keyboardFocus: ThawBarKeyboardFocus,
        screen: NSScreen,
        section: MenuBarSection.Name,
        showsOnlyThawBarOnlyItems: Bool,
        folderMembers: [String]?
    ) {
        super.init(
            rootView: Self.makeContentView(
                appState: appState,
                colorManager: colorManager,
                keyboardFocus: keyboardFocus,
                screen: screen,
                section: section,
                showsOnlyThawBarOnlyItems: showsOnlyThawBarOnlyItems,
                folderMembers: folderMembers
            )
        )
    }

    /// Reuse the hosting graph with new inputs; rebuilding on each show grows process-lifetime SwiftUI caches.
    func update(
        appState: AppState,
        colorManager: ThawBarColorManager,
        keyboardFocus: ThawBarKeyboardFocus,
        screen: NSScreen,
        section: MenuBarSection.Name,
        showsOnlyThawBarOnlyItems: Bool,
        folderMembers: [String]?
    ) {
        rootView = Self.makeContentView(
            appState: appState,
            colorManager: colorManager,
            keyboardFocus: keyboardFocus,
            screen: screen,
            section: section,
            showsOnlyThawBarOnlyItems: showsOnlyThawBarOnlyItems,
            folderMembers: folderMembers
        )
    }

    private static func makeContentView(
        appState: AppState,
        colorManager: ThawBarColorManager,
        keyboardFocus: ThawBarKeyboardFocus,
        screen: NSScreen,
        section: MenuBarSection.Name,
        showsOnlyThawBarOnlyItems: Bool,
        folderMembers: [String]?
    ) -> ThawBarContentView {
        ThawBarContentView(
            appState: appState,
            colorManager: colorManager,
            keyboardFocus: keyboardFocus,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            visibleControlItem: appState.menuBarManager.section(withName: .visible)?.controlItem,
            screen: screen,
            section: section,
            showsOnlyThawBarOnlyItems: showsOnlyThawBarOnlyItems,
            folderMembers: folderMembers
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView _: ThawBarContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - ThawBarContentView

/// What the keyboard highlight has to follow: the item count and layout.
private struct KeyboardLayoutKey: Equatable {
    let count: Int
    let layout: ThawBarLayout
    let columns: Int
}

private struct ThawBarContentView: View {
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
            displayID: screen.displayID,
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
