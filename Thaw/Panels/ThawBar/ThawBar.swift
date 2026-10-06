//
//  ThawBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel

final class ThawBarPanel: NSPanel {
    private let diagLog = DiagLog(category: "ThawBarPanel")
    private weak var appState: AppState?

    private let colorManager = ThawBarColorManager()
    private let pointerLocation: @MainActor () -> CGPoint?
    private let pointerInEmptyMenuBarSpace: @MainActor (AppState, NSScreen) -> Bool

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

    /// The pointer's x when the bar opened at the pointer. Resizes reposition the panel, and
    /// re-reading a pointer that has since moved off empty menu bar space would resolve Dynamic
    /// to the Thaw icon, or to the right edge while that icon is hidden.
    private var openingPointerX: CGFloat?

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

    private static func livePointerInEmptyMenuBarSpace(_ appState: AppState, _ screen: NSScreen) -> Bool {
        appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen)
    }

    init(
        pointerLocation: @escaping @MainActor () -> CGPoint? = { MouseHelpers.locationAppKit },
        pointerInEmptyMenuBarSpace: @escaping @MainActor (AppState, NSScreen) -> Bool = ThawBarPanel.livePointerInEmptyMenuBarSpace
    ) {
        self.pointerLocation = pointerLocation
        self.pointerInEmptyMenuBarSpace = pointerInEmptyMenuBarSpace
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
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .replace(with: ()),
            DisplayTopology.shared.screenParametersChanged
        )
        .sink { [weak self] in
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
        if hotkeyLocationOverride, let mouse = pointerLocation() {
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
                && pointerInEmptyMenuBarSpace(appState, screen),
            hasPointerLocation: pointerLocation() != nil,
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
        if let openingPointerX {
            return CGPoint(x: (openingPointerX - frame.width / 2).clamped(to: xRange), y: y)
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
            pointerLocation().map { $0.x - frame.width / 2 }
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
        let location = appState.settings.displaySettings.thawBarLocation(for: screen.displayID)
        let opensAtPointer = Self.concreteLocation(
            for: location,
            pointerInEmptyMenuBarSpace: location == .dynamic
                && pointerInEmptyMenuBarSpace(appState, screen),
            hasPointerLocation: pointerLocation() != nil,
            showsThawIcon: appState.settings.general.showThawIcon
        ) == .mousePointer
        openingPointerX = opensAtPointer ? pointerLocation()?.x : nil

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
