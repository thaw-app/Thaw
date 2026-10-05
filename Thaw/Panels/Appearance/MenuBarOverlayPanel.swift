//
//  MenuBarOverlayPanel.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AsyncAlgorithms
import Cocoa
import Combine
import MenuBarModel

private final class MenuBarLiquidGlassFadeView: NSView {
    var isEnabled = false {
        didSet {
            needsDisplay = oldValue != isEnabled
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isEnabled,
              let context = NSGraphicsContext.current?.cgContext,
              let gradient = CGGradient(
                  colorsSpace: CGColorSpace(name: CGColorSpace.displayP3),
                  // Keep the upper third dense for legible titles on bright wallpaper; reveal glass through the lower half.
                  colors: [
                      NSColor.black.withAlphaComponent(0.96).cgColor,
                      NSColor.black.withAlphaComponent(0.88).cgColor,
                      NSColor.black.withAlphaComponent(0.42).cgColor,
                      NSColor.clear.cgColor,
                  ] as CFArray,
                  locations: [0, 0.3, 0.62, 1]
              )
        else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.minY),
            end: CGPoint(x: bounds.midX, y: bounds.maxY),
            options: []
        )
    }
}

final class MenuBarLiquidGlassContainerView: NSView {
    private var glassViews = [NSGlassEffectView]()
    private let fadeView = MenuBarLiquidGlassFadeView()
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.mask = maskLayer
        fadeView.autoresizingMask = [.width, .height]
        addSubview(fadeView)
        borderLayer.fillColor = nil
        borderLayer.zPosition = 1
        layer?.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        path: CGPath,
        isColored: Bool,
        tintColor: CGColor,
        tintOpacity: Double,
        effectOpacity: Double,
        usesDarkFade: Bool,
        borderColor: CGColor?,
        borderWidth: Double,
        borderStyle: MenuBarBorderStyle = .solid
    ) {
        let componentBounds = MenuBarLiquidGlassGeometry.componentBounds(of: path)
        while glassViews.count < componentBounds.count {
            let glassView = NSGlassEffectView()
            glassView.style = .clear
            addSubview(glassView, positioned: .below, relativeTo: fadeView)
            glassViews.append(glassView)
        }

        for (index, glassView) in glassViews.enumerated() {
            guard index < componentBounds.count else {
                glassView.isHidden = true
                continue
            }
            let componentBounds = componentBounds[index]
            glassView.frame = componentBounds
            glassView.cornerRadius = min(componentBounds.width, componentBounds.height) / 2
            glassView.alphaValue = effectOpacity
            glassView.tintColor = isColored
                ? NSColor(cgColor: tintColor)?.withAlphaComponent(tintOpacity)
                : nil
            glassView.isHidden = false
        }

        fadeView.frame = bounds
        fadeView.isEnabled = usesDarkFade
        maskLayer.frame = bounds
        maskLayer.path = path
        borderLayer.frame = bounds
        borderLayer.path = path
        borderLayer.strokeColor = borderColor
        borderLayer.lineWidth = borderWidth * 2
        borderLayer.lineDashPattern = borderStyle.dashPattern(width: borderWidth)?.map { NSNumber(value: Double($0)) }
        borderLayer.isHidden = borderColor == nil
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

// MARK: - Overlay Panel

/// One transparent appearance overlay per screen, taking neither focus nor mouse events.
/// MenuBarAppearanceManager constructs it on MainActor; isolated instance members make it Sendable without unchecked conformance.
@MainActor
final class MenuBarOverlayPanel: NSPanel {
    private let diagLog = DiagLog(category: "MenuBarOverlayPanel")

    /// Debounce repeated show requests and clear them after positioning the panel.
    @Published var needsShow = false

    /// Track per-display fullscreen bar absence separately; another app's fullscreen transition does not change Thaw's presentation options.
    private var isSystemMenuBarAbsent = false

    /// The Mission Control probe, which owns the probe window and the state
    /// that decides when the overlay should fade.
    private let missionControlProbe: MissionControlShieldProbe

    /// Where the frontmost app's menus sit in the menu bar, in screen
    /// coordinates, or nil while that is not known.
    @Published private(set) var applicationMenuFrame: CGRect?

    private var cancellables = Set<AnyCancellable>()

    /// The in-flight settle-polling of the application menu frame, at most
    /// one at a time; a fresh app switch displaces the previous poll.
    private var menuFrameSettleTask: Task<Void, Never>?

    /// Retry task for show() when it fails due to unsettled Window Server.
    private var showRetryTask: Task<Void, Never>?

    private(set) weak var appState: AppState?

    /// The screen whose menu bar this panel covers.
    let owningScreen: NSScreen

    private var shouldPollMissionControlProbe: Bool {
        // Keep polling active probes even at alpha 0; wallpaper desktop reveal displaces the probe without a Space change.
        appState != nil && (alphaValue > 0 || missionControlProbe.isActive)
    }

    /// Transparent, nonactivating panel excluded from window menus and cycling; order it only when needsShow requests.
    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
        self.missionControlProbe = MissionControlShieldProbe(owningScreen: owningScreen)
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless, .fullSizeContentView, .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.title = String(localized: "Menu Bar Overlay")
        self.backgroundColor = .clear
        self.hasShadow = false
        self.animationBehavior = .none
        self.hidesOnDeactivate = false
        self.canHide = false
        self.isMovable = false
        self.ignoresMouseEvents = true
        self.isExcludedFromWindowsMenu = true
        // Without .canJoinAllSpaces the overlay exists only on the Space it
        // was created on; nothing re-attaches it on a Space change.
        self.collectionBehavior = [
            .fullScreenNone, .ignoresCycle, .stationary, .canJoinAllSpaces,
        ]
        self.contentView = MenuBarOverlayPanelContentView()
        missionControlProbe.shouldRun = { [weak self] in self?.shouldPollMissionControlProbe ?? false }
        configureCancellables()

        missionControlProbe.start()
    }

    private func configureCancellables() {
        var subscriptions = [
            observeActiveSpaceChanges(),
            observeMenuOwningApplication(),
            observeSpaceEntry(),
            refreshApplicationMenuFramePeriodically(),
            observeShowRequests(),
        ]
        if let appState {
            subscriptions.append(observeMenuBarVisibility(appState: appState))
            subscriptions.append(observeConfigurationForWindowLevel(appState: appState))
        }
        cancellables = Set(subscriptions)

        updateMissionControlProbePolling()
    }

    /// Asynchronous layout can initially return the outgoing app's frame; poll for three stable reads, capped at ten.
    /// Non-main screens need one read because only the main bar reflows on app switches.
    private func trackApplicationMenuFrame() {
        menuFrameSettleTask?.cancel()
        menuFrameSettleTask = Task { @MainActor [weak self] in
            var candidate: CGRect?
            var settledCount = 0
            for _ in 0 ..< 10 {
                guard !Task.isCancelled, let self else { return }
                if let latest = owningScreen.getApplicationMenuFrame(bypassCache: true) {
                    if latest == candidate {
                        settledCount += 1
                        if settledCount >= 3 {
                            return
                        }
                    } else {
                        applicationMenuFrame = latest
                        candidate = latest
                        settledCount = 0
                    }
                }
                if owningScreen != NSScreen.main {
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Space changes reshow the panel and clear Mission Control state the probe may not detect.
    private func observeActiveSpaceChanges() -> AnyCancellable {
        let (spaceChangeEvents, spaceChangeContinuation) = AsyncStream<Void>.makeStream()
        let task = Task { @MainActor [weak self] in
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { _ in spaceChangeContinuation.yield(()) }
            defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            for await _ in spaceChangeEvents.debounce(for: .seconds(0.1)) {
                guard let self else { return }
                self.missionControlProbe.isActive = false
                self.needsShow = true
                // Fullscreen transitions change bar presence mid-animation; recheck after settling.
                for delay in [Duration.zero, .milliseconds(400), .milliseconds(1200)] {
                    do {
                        try await Task.sleep(for: delay)
                    } catch {
                        return
                    }
                    self.refreshSystemMenuBarPresence()
                }
            }
        }
        return AnyCancellable { task.cancel() }
    }

    /// Starts or stops the probe poll to match
    /// shouldPollMissionControlProbe.
    private func updateMissionControlProbePolling() {
        missionControlProbe.updatePolling(isWanted: shouldPollMissionControlProbe)
    }

    /// Probe rate based on time at rest; see MissionControlShieldProbe.tickInterval(atRestFor:).
    static nonisolated func missionControlProbeTickInterval(atRestFor restDuration: TimeInterval?) -> TimeInterval {
        MissionControlShieldProbe.tickInterval(atRestFor: restDuration)
    }

    /// Re-reads the application menu frame when the app owning the menu bar,
    /// or the frontmost app, changes.
    private func observeMenuOwningApplication() -> AnyCancellable {
        Publishers.Merge(
            NSWorkspace.shared.publisher(
                for: \.menuBarOwningApplication,
                options: .old
            )
            .combineLatest(
                NSWorkspace.shared.publisher(
                    for: \.menuBarOwningApplication,
                    options: .new
                )
            )
            .compactMap { $0 == $1 ? nil : $0 },
            NSWorkspace.shared.publisher(
                for: \.frontmostApplication,
                options: .old
            )
            .combineLatest(
                NSWorkspace.shared.publisher(
                    for: \.frontmostApplication,
                    options: .new
                )
            )
            .compactMap { $0 == $1 ? nil : $0 }
        )
        .removeDuplicates()
        .sink { [weak self] _ in
            self?.trackApplicationMenuFrame()
        }
    }

    /// Re-reads the application menu frame once the panel is on the active
    /// Space, whether the user switched to it or dragged a window into it.
    private func observeSpaceEntry() -> AnyCancellable {
        Publishers.Merge(
            publisher(for: \.isOnActiveSpace)
                .receive(on: DispatchQueue.main)
                .replace(with: ()),
            EventMonitor.publish(events: .leftMouseUp, scope: .universal)
                .filter { [weak self] _ in self?.isOnActiveSpace ?? false }
                .replace(with: ())
        )
        .debounce(for: 0.05, scheduler: DispatchQueue.main)
        .sink { [weak self] in
            self?.refreshApplicationMenuFrame()
        }
    }

    /// Re-reads the application menu frame on a slow timer, as a backstop for
    /// changes none of the other triggers noticed.
    private func refreshApplicationMenuFramePeriodically() -> AnyCancellable {
        Timer.publish(every: 60, tolerance: 10, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isOnActiveSpace else {
                    return
                }
                self.refreshApplicationMenuFrame()
            }
    }

    /// Acts on needsShow, collapsing a burst of requests into one show.
    private func observeShowRequests() -> AnyCancellable {
        $needsShow
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .filter(\.self)
            .sink { [weak self] _ in
                guard let self else { return }
                show()
                needsShow = false
            }
    }

    /// Fade when macOS hides the bar or Mission Control takes the screen.
    /// Observe MenuBarManager and the Published probe separately; each update reads both current values.
    private func observeMenuBarVisibility(appState: AppState) -> AnyCancellable {
        func applyVisibility(_ self: MenuBarOverlayPanel, menuBarManager _: MenuBarManager) {
            self.applyVisibility()
        }
        let task = Task { @MainActor [weak self, menuBarManager = appState.menuBarManager] in
            let changes = Observations { menuBarManager.isMenuBarHiddenBySystem }
            for await _ in changes {
                guard let self else { return }
                applyVisibility(self, menuBarManager: menuBarManager)
            }
        }
        let missionControlCancellable = missionControlProbe.$isActive
            .sink { [weak self, weak menuBarManager = appState.menuBarManager] _ in
                guard let self, let menuBarManager else { return }
                applyVisibility(self, menuBarManager: menuBarManager)
            }
        return AnyCancellable {
            task.cancel()
            missionControlCancellable.cancel()
        }
    }

    /// Observe effective appearance for window-level changes; wrap the task in the panel's cancellable set.
    private func observeConfigurationForWindowLevel(appState: AppState) -> AnyCancellable {
        let task = Task { @MainActor [weak self, appearanceManager = appState.appearanceManager] in
            let changes = Observations { appearanceManager.effectiveConfiguration }
            for await _ in changes {
                guard let self else { return }
                updateWindowLevel()
            }
        }
        return AnyCancellable { task.cancel() }
    }

    /// Skip frame reads during teardown (pipelines can still fire) or system hiding, when geometry is not on screen.
    private func refreshApplicationMenuFrame() {
        guard
            let menuBarManager = appState?.menuBarManager,
            !menuBarManager.isMenuBarHiddenBySystem
        else {
            return
        }
        applicationMenuFrame = owningScreen.getApplicationMenuFrame()
    }

    /// Whether there is currently a menu bar for the panel to sit on.
    private var hasMenuBarToCover: Bool {
        guard let menuBarManager = appState?.menuBarManager else { return true }
        return !menuBarManager.isMenuBarHiddenBySystem
            && !missionControlProbe.isActive
            && !isSystemMenuBarAbsent
    }

    private func applyVisibility() {
        alphaValue = hasMenuBarToCover ? 1 : 0
        updateMissionControlProbePolling()
    }

    private func refreshSystemMenuBarPresence() {
        // Entering or leaving a fullscreen Space changes which level keeps the panel under the items.
        updateWindowLevel()
        let absent = Self.isSystemMenuBarHidden(on: owningScreen)
        guard absent != isSystemMenuBarAbsent else { return }
        isSystemMenuBarAbsent = absent
        diagLog.debug("Overlay: system menu bar on display \(owningScreen.displayID) is \(absent ? "hidden" : "shown")")
        applyVisibility()
    }

    /// Use fullscreen Space reveal state, defaulting to shown when unavailable.
    /// macOS 27's main bar has no enumerable window even while visible.
    private static func isSystemMenuBarHidden(on screen: NSScreen) -> Bool {
        guard
            let spaceID = Bridging.getCurrentSpaceID(for: screen.displayID),
            Bridging.isSpaceFullscreen(spaceID)
        else {
            return false
        }
        let state = Bridging.menuBarRevealState(forSpace: spaceID)
        return state.isAvailable && !state.isVisible && state.revealFraction <= 0
    }

    /// Read height at show time because it changes with the screen; retry unavailable geometry during display reconfiguration.
    private func show() {
        guard let appState else {
            return
        }

        guard appState.appearanceManager.overlayPanels.contains(self) else {
            diagLog.warning("Overlay panel \(self) not retained")
            return
        }

        guard let menuBarHeight = owningScreen.getMenuBarHeight() else {
            scheduleShowRetry()
            return
        }

        showRetryTask?.cancel()
        showRetryTask = nil

        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarHeight) - 5,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5
        )

        updateWindowLevel()
        alphaValue = 0
        setFrame(newFrame, display: true)
        orderFrontRegardless()

        refreshApplicationMenuFrame()
        refreshSystemMenuBarPresence()
        applyVisibility()
    }

    /// Keep only the latest delayed show retry while Window Server geometry settles; success cancels it.
    private func scheduleShowRetry() {
        showRetryTask?.cancel()
        showRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.needsShow = true }
        }
    }

    /// Clear retained state during teardown; owningScreen remains immutable.
    private func cleanupReferences() {
        applicationMenuFrame = nil
        missionControlProbe.reset()
    }

    override func close() {
        showRetryTask?.cancel()
        showRetryTask = nil
        menuFrameSettleTask?.cancel()
        menuFrameSettleTask = nil
        cancellables.removeAll()
        cleanupReferences()
        contentView = nil
        missionControlProbe.close()
        super.close()
        #if DEBUG
            diagLog.debug("Overlay panel closed. Active windows: \(NSApplication.shared.windows.count)")
        #endif
    }

    /// Moves the panel behind the menu bar whenever a tint or shape is active
    /// so the menu bar's own blur blends the content and items stay crisp.
    private func updateWindowLevel() {
        guard let appState else { return }
        let config = appState.appearanceManager.effectiveConfiguration
        let hasAppearance = config.current.tintKind != .noTint
            || config.shapeKind != .noShape
            || config.current.backgroundKind != .none
        let newLevel = Self.overlayLevel(
            hasAppearance: hasAppearance,
            isFullscreenSpace: Self.isFullscreenSpace(on: owningScreen)
        )
        if level != newLevel {
            level = newLevel
        }
    }

    private static func isFullscreenSpace(on screen: NSScreen) -> Bool {
        guard let spaceID = Bridging.getCurrentSpaceID(for: screen.displayID) else { return false }
        return Bridging.isSpaceFullscreen(spaceID)
    }

    /// The level that keeps an appearance under the menu bar's items.
    /// A fullscreen Space draws its bar at the main-menu level, where an equal-level panel ordered front covers the items.
    static nonisolated func overlayLevel(hasAppearance: Bool, isFullscreenSpace: Bool) -> NSWindow.Level {
        guard hasAppearance else { return .statusBar }
        let key: CGWindowLevelKey = isFullscreenSpace ? .mainMenuWindow : .statusWindow
        return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(key)) - 1)
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}

// MARK: - Content View

private final class MenuBarOverlayPanelContentView: NSView {
    @Published private var fullConfiguration: MenuBarAppearanceConfigurationV2 =
        .defaultConfiguration

    @Published private var previewConfiguration:
        MenuBarAppearancePartialConfiguration?

    @Published private var averageColorInfo: MenuBarAverageColorInfo?

    /// The dominant colors of the wallpaper behind this panel's screen, for
    /// the adaptive gradient tint. nil until the first palette capture lands.
    @Published private var wallpaperPalette: WallpaperPalette?

    private var cancellables = Set<AnyCancellable>()

    /// macOS 27 NSView animator alpha finishes in one frame regardless of duration or layer backing; window alpha still works.
    /// Set model alpha directly and use CABasicAnimation opacity for the fade.
    private func fadeAlpha(to target: CGFloat, duration: CFTimeInterval = 0.25) {
        wantsLayer = true
        guard let layer else {
            alphaValue = target
            return
        }
        let from = layer.presentation()?.opacity ?? Float(alphaValue)
        alphaValue = target
        guard abs(from - Float(target)) > 0.001 else {
            layer.removeAnimation(forKey: Self.alphaFadeKey)
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = Float(target)
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: Self.alphaFadeKey)
    }

    private static let alphaFadeKey = "thawAlphaFade"

    private lazy var tintGlassView: NSGlassEffectView = {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        view.contentView = content
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }()

    private lazy var tintLiquidGlassView: MenuBarLiquidGlassContainerView = {
        let view = MenuBarLiquidGlassContainerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var backgroundLiquidGlassView: MenuBarLiquidGlassContainerView = {
        let view = MenuBarLiquidGlassContainerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var tintGlassMaskLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillRule = .evenOdd
        return layer
    }()

    private lazy var tintGlassContentMaskLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillRule = .evenOdd
        return layer
    }()

    private lazy var tintGlassBorderLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        return layer
    }()

    private var shapeCGPath: CGPath?

    /// Use fresh AXExtrasMenuBar geometry: Apple items may stay visible while Hidden, and conceal snapshots may retain stale bounds.
    private var cachedAXItemBounds: [CGRect] = []
    private var cachedAXSourceScreenFrame: CGRect?

    /// Keep the concealed chevron separate so widening the trailing pill cannot pull the leading pill's clamp over real items.
    /// Zero during Hidden reveal, when cachedAXItemBounds already includes the chevron.
    private var cachedChevronFrame: CGRect = .zero

    /// Last successfully drawn split-pill rectangles. Used while geometry is
    /// frozen or when a transitional AX read would intersect / fall back to full.
    private var lastStableLeadingPathBounds: CGRect = .zero
    private var lastStableTrailingPathBounds: CGRect = .zero

    /// When true, pathForSplitShape keeps drawing lastStableLeadingPathBounds
    /// and lastStableTrailingPathBounds until the pending AX refresh finishes.
    private var splitPillGeometryFrozen = false

    /// The last live edge reported by the edge watcher, and when.
    private var leadingEdgeSeen: (sample: MenuBarLeadingEdgeSample, at: ContinuousClock.Instant)?

    private lazy var geometryRefresh = MenuBarGeometryRefresh(
        read: { [weak self] minimumReadTime in
            await self?.readAXItemBounds(notBefore: minimumReadTime)
        },
        publish: { [weak self] snapshot in
            guard let self else { return }
            cachedAXItemBounds = snapshot.itemBounds
            cachedAXSourceScreenFrame = snapshot.sourceScreenFrame
            cachedChevronFrame = snapshot.chevronFrame
            // A read that began before the edge last moved describes the bar
            // as it was; the live edge is newer.
            if let edge = leadingEdgeSeen, edge.at > snapshot.readAt {
                followLeadingEdge(to: edge.sample)
            }
        },
        setPending: { [weak self] pending in
            self?.splitPillGeometryFrozen = pending
            self?.needsDisplay = true
        }
    )

    /// The panel this view is the content of, if it has been installed in one.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The colors to draw with: the live preview while one is up, and the
    /// stored configuration for the current appearance otherwise.
    private var configuration: MenuBarAppearancePartialConfiguration {
        if let appState = overlayPanel?.appState,
           let preview = appState.appearanceManager.previewConfiguration
        {
            return preview
        }
        return fullConfiguration.current
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCancellables()
    }

    private func configureCancellables() {
        geometryRefresh.cancel()
        var subscriptions = Set<AnyCancellable>()

        if let overlayPanel {
            if let appState = overlayPanel.appState {
                // Observe effective and preview configuration together; effectiveConfiguration also covers Space overrides.
                let task = Task { @MainActor [weak self, appearanceManager = appState.appearanceManager] in
                    let changes = Observations {
                        (appearanceManager.effectiveConfiguration, appearanceManager.previewConfiguration)
                    }
                    for await (full, preview) in changes {
                        guard let self else { return }
                        if fullConfiguration != full {
                            fullConfiguration = full
                        }
                        if previewConfiguration != preview {
                            previewConfiguration = preview
                        }
                    }
                }
                AnyCancellable { task.cancel() }
                    .store(in: &subscriptions)

                let colorsTask = Task { @MainActor [weak self, menuBarManager = appState.menuBarManager] in
                    let changes = Observations { menuBarManager.averageColors }
                    for await colors in changes {
                        guard let self, let panel = self.overlayPanel else { return }
                        averageColorInfo = colors[panel.owningScreen.displayID]
                    }
                }
                AnyCancellable { colorsTask.cancel() }
                    .store(in: &subscriptions)

                let palettesTask = Task { @MainActor [weak self, menuBarManager = appState.menuBarManager] in
                    let changes = Observations { menuBarManager.wallpaperPalettes }
                    for await palettes in changes {
                        guard let self, let panel = self.overlayPanel else { return }
                        wallpaperPalette = palettes[panel.owningScreen.displayID]
                    }
                }
                AnyCancellable { palettesTask.cancel() }
                    .store(in: &subscriptions)

                // Hide during drags so the real menu bar remains visible; dedupe AppState observations manually.
                let dragTask = Task { @MainActor [weak self, weak appState] in
                    guard let appState else { return }
                    let changes = Observations { appState.isDraggingMenuBarItem }
                    var previous: Bool?
                    for await isDragging in changes {
                        guard let self else { return }
                        guard isDragging != previous else { continue }
                        previous = isDragging
                        fadeAlpha(to: isDragging ? 0 : 1)
                    }
                }
                AnyCancellable { dragTask.cancel() }
                    .store(in: &subscriptions)

                for section in appState.menuBarManager.sections {
                    // Watch settled onScreenFrame, not isHidden, which flips before items finish moving.
                    section.controlItem.$onScreenFrame
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            // Freeze while the bar re-settles so a transient AX
                            // read doesn't flash wrong bounds.
                            self?.splitPillGeometryFrozen = true
                            self?.scheduleAXItemBoundsRefresh()
                        }
                        .store(in: &subscriptions)
                }

                // Refresh macOS 27 physical AX geometry after cache changes; dedupe observations manually.
                let cacheTask = Task { @MainActor [weak self, itemManager = appState.itemManager] in
                    let changes = Observations { itemManager.itemCache }
                    var previous: MenuBarItemManager.ItemCache?
                    for await cache in changes {
                        guard let self else { return }
                        guard cache != previous else { continue }
                        previous = cache
                        // Freeze so a transient AX read during the
                        // cache-change reflow doesn't flash wrong bounds.
                        splitPillGeometryFrozen = true
                        scheduleAXItemBoundsRefresh()
                    }
                }
                AnyCancellable { cacheTask.cancel() }
                    .store(in: &subscriptions)

                // The direct edge watcher avoids cache-walk delays after external changes.
                let edgeTask = Task { @MainActor [weak self, watcher = appState.menuBarManager.leadingEdgeWatcher] in
                    for await edge in Observations({ watcher.leadingEdge }) {
                        guard let self, let edge else { continue }
                        leadingEdgeSeen = (edge, .now)
                        followLeadingEdge(to: edge)
                    }
                }
                AnyCancellable { edgeTask.cancel() }
                    .store(in: &subscriptions)

                appState.menuBarManager.revealedSectionChanges
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] revealed in
                        guard let self else { return }
                        // Hold stable geometry during reflow; intersecting or empty AX reads can flash a full-width fallback.
                        splitPillGeometryFrozen = true
                        needsDisplay = true
                        scheduleAXItemBoundsRefresh(.visibilityChanged(isRevealed: revealed != nil))
                    }
                    .store(in: &subscriptions)
            }

            // Menu movement can accompany external item additions or removals; refresh item geometry too.
            overlayPanel.$applicationMenuFrame
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.needsDisplay = true
                    self.scheduleAXItemBoundsRefresh()
                }
                .store(in: &subscriptions)
        }

        $fullConfiguration.replace(with: ())
            .merge(with: $previewConfiguration.replace(with: ()))
            .merge(with: $averageColorInfo.replace(with: ()))
            .merge(with: $wallpaperPalette.replace(with: ()))
            .sink { [weak self] _ in
                self?.updateBackgroundGlass()
                self?.needsDisplay = true
            }
            .store(in: &subscriptions)

        cancellables = subscriptions

        // Populate before the first draw.
        scheduleAXItemBoundsRefresh(.immediate)
    }

    /// Trim or extend cached bounds to the live leading edge; full AX walks take seconds and restart on changes.
    /// The right edge stays screen-pinned; the next full refresh replaces these provisional bounds.
    private func followLeadingEdge(to sample: MenuBarLeadingEdgeSample) {
        guard let panel = overlayPanel, let appState = panel.appState else { return }
        let updated = MenuBarSplitPillGeometry.followingVisibleEdge(
            sample,
            itemBounds: cachedAXItemBounds,
            stableTrailingBounds: lastStableTrailingPathBounds,
            screenFrame: panel.owningScreen.cgFrame,
            revealedSection: appState.menuBarManager.sectionController.revealedSection,
            isTransitioning: appState.menuBarManager.isRevealHideTransitionActive,
            sourceScreenFrame: cachedAXSourceScreenFrame
        )
        cachedAXItemBounds = updated.itemBounds
        lastStableTrailingPathBounds = updated.stableTrailingBounds
        needsDisplay = true
    }

    private func scheduleAXItemBoundsRefresh(
        _ event: MenuBarGeometryRefresh.Event = .geometryChanged
    ) {
        guard overlayPanel != nil else {
            geometryRefresh.cancel()
            cachedAXItemBounds = []
            cachedAXSourceScreenFrame = nil
            cachedChevronFrame = .zero
            return
        }
        geometryRefresh.schedule(event)
    }

    private func readAXItemBounds(notBefore minimumReadTime: ContinuousClock.Instant?) async -> MenuBarGeometryRefresh.Snapshot? {
        guard let displayID = overlayPanel?.owningScreen.displayID else { return nil }
        let displayBounds = CGDisplayBounds(displayID)
        let itemManager = overlayPanel?.appState?.itemManager
        guard let snapshot = await MenuBarAppearanceItems.read(
            knownItems: itemManager?.managedItems ?? [],
            onScreenSnapshot: itemManager?.onScreenItemSnapshot,
            notBefore: minimumReadTime,
            readOwners: { await MenuBarItemAXProvider.menuBarItemsForAppearanceConcurrent(knownOwners: $0) },
            discover: {
                await MenuBarItem.getMenuBarItems(
                    on: displayID, option: [.onScreen, .activeSpace], resolveSourcePID: false
                )
            }
        ), !Task.isCancelled else { return nil }
        let controller = overlayPanel?.appState?.menuBarManager.sectionController
        let context = MenuBarSplitPillGeometry.TrailingPillContext(
            revealedSection: controller?.revealedSection,
            section: { item in
                controller?.section(for: item) ?? .visible
            }
        )
        return MenuBarAppearanceItems.geometry(
            from: snapshot,
            on: displayBounds,
            displayBounds: NSScreen.allDisplayBoundsCG,
            context: context
        )
    }

    /// Use debounced physical AX geometry, not CGS windows or logical sections, to wrap what is actually present.
    /// Apple Hidden items can remain visible, while conceal snapshots retain stale bounds.
    private func trailingContentItemBounds() -> [CGRect] {
        cachedAXItemBounds
    }

    /// Avoid double-counting overlay origins; cap at the first status item so macOS 27 menu unions cannot stretch the pill.
    private func computeLeadingPathBounds(
        applicationMenuFrame: CGRect,
        trailingContentMinX: CGFloat?,
        in rect: CGRect,
        shouldInset: Bool,
        leadingEndCap: MenuBarEndCap,
        screen: NSScreen,
        appearanceManager: MenuBarAppearanceManager
    ) -> CGRect {
        let trailingPadding: CGFloat = {
            if shouldInset {
                var padding: CGFloat = 10
                if leadingEndCap == .square {
                    padding += appearanceManager.menuBarInsetAmount
                }
                return padding
            }
            return 12
        }()

        // Use AX's CGDisplayBounds space; scaled resolutions can make AppKit frames clip or drop required item bounds.
        let screenFrame = CGDisplayBounds(screen.displayID)

        return MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: applicationMenuFrame,
            trailingContentMinX: trailingContentMinX,
            in: rect,
            screenFrame: screenFrame,
            trailingPadding: trailingPadding,
            leadingMargin: fullConfiguration.leftMargin,
            notchFrame: screen.frameOfNotch,
            notchMargin: fullConfiguration.notchMargin
        )
    }

    /// Use the union, not summed widths, so inter-icon gaps do not leave leftmost items outside the pill.
    private func computeTrailingPathBounds(
        itemBounds: [CGRect],
        in rect: CGRect,
        shouldInset: Bool,
        trailingEndCap: MenuBarEndCap,
        screen: NSScreen,
        appearanceManager: MenuBarAppearanceManager
    ) -> CGRect {
        guard !itemBounds.isEmpty else { return .zero }

        // Use AX's CGDisplayBounds space; scaled resolutions can make AppKit frames clip or drop required item bounds.
        let screenFrame = CGDisplayBounds(screen.displayID)
        let displayItemBounds = itemBounds.filter { bounds in
            bounds.midX >= screenFrame.minX && bounds.midX <= screenFrame.maxX
        }
        guard !displayItemBounds.isEmpty else { return .zero }

        let leadingOutset: CGFloat = {
            if shouldInset {
                var outset: CGFloat = 4
                if trailingEndCap == .square {
                    outset += appearanceManager.menuBarInsetAmount
                }
                return outset
            }
            // AX frames include button padding; use a small inner margin to clear the cap without an empty leading shelf.
            return Constants.MenuBarTuning.trailingPillLeadingInnerMargin
        }()
        let trailingOutset: CGFloat = {
            if shouldInset {
                return 4
            }
            // macOS 27 needs enough outer margin for the rounded cap to clear the rightmost Clock item.
            return Constants.MenuBarTuning.trailingPillTrailingOuterMargin
        }()

        return MenuBarSplitPillGeometry.trailingBounds(
            itemBounds: displayItemBounds,
            in: rect,
            screenFrame: screenFrame,
            leadingOutset: leadingOutset,
            trailingOutset: trailingOutset,
            notchFrame: screen.frameOfNotch,
            notchMargin: fullConfiguration.notchMargin
        )
    }

    private func pathForSplitShape(
        in rect: CGRect,
        info: MenuBarSplitShapeInfo,
        isInset: Bool,
        screen: NSScreen
    ) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager
        else {
            return NSBezierPath()
        }
        let shouldInset = isInset && screen.hasNotch
        let rect = MenuBarShapePathBuilder.insetForNotch(
            rect,
            outerCaps: info.outerEndCaps,
            isInset: isInset,
            screen: screen,
            amount: appearanceManager.menuBarInsetAmount
        )

        let computedLeadingPathBounds: CGRect = {
            guard
                let applicationMenuFrame = overlayPanel?.applicationMenuFrame,
                applicationMenuFrame.width > 0
            else {
                return .zero
            }
            let trailingContentMinX = trailingContentItemBounds().map(\.minX).min()
            return computeLeadingPathBounds(
                applicationMenuFrame: applicationMenuFrame,
                trailingContentMinX: trailingContentMinX,
                in: rect,
                shouldInset: shouldInset,
                leadingEndCap: info.leading.leadingEndCap,
                screen: screen,
                appearanceManager: appearanceManager
            )
        }()
        let computedTrailingPathBounds: CGRect = {
            var itemBounds = trailingContentItemBounds()
            // Widen only the trailing pill, not the leading clamp; ignore chevrons temporarily reflowed left of real candidates.
            if !cachedChevronFrame.isEmpty {
                let existingMinX = itemBounds.map(\.minX).min()
                if existingMinX.map({ cachedChevronFrame.minX >= $0 }) ?? true {
                    itemBounds.append(cachedChevronFrame)
                }
            }
            return computeTrailingPathBounds(
                itemBounds: itemBounds,
                in: rect,
                shouldInset: shouldInset,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen,
                appearanceManager: appearanceManager
            )
        }()

        let resolvedBounds = MenuBarSplitPillGeometry.resolveSplitPathBounds(
            leading: computedLeadingPathBounds,
            trailing: computedTrailingPathBounds,
            geometryFrozen: splitPillGeometryFrozen,
            lastStableLeading: lastStableLeadingPathBounds,
            lastStableTrailing: lastStableTrailingPathBounds
        )
        lastStableLeadingPathBounds = resolvedBounds.nextStableLeading
        lastStableTrailingPathBounds = resolvedBounds.nextStableTrailing

        return MenuBarShapePathBuilder.splitShapePath(
            leadingPathBounds: resolvedBounds.leading,
            trailingPathBounds: resolvedBounds.trailing,
            info: info,
            in: rect,
            leftMargin: fullConfiguration.leftMargin,
            rightMargin: fullConfiguration.rightMargin,
            screen: screen
        )
    }

    /// Returns the bounds that the view's drawn content can occupy.
    private func getDrawableBounds() -> CGRect {
        return CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )
    }

    /// Draws the tint defined by the given configuration in the given rectangle.
    private func drawTint(in rect: CGRect) {
        switch configuration.tintKind {
        case .noTint:
            break
        case .glass:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: configuration.tintColor)?
                .withAlphaComponent(configuration.tintOpacity)
            {
                tintColor.setFill()
                rect.fill()
            }
        case .gradient:
            if let tintGradient = configuration.tintGradient
                .withAlpha(configuration.tintOpacity)
                .nsGradient(using: .displayP3)
            {
                tintGradient.draw(in: rect, angle: 0)
            }
        case .adaptive:
            if let colorInfo = averageColorInfo,
               let color = NSColor(cgColor: colorInfo.color)?
               .withAlphaComponent(configuration.tintOpacity)
            {
                color.setFill()
                rect.fill()
            }
        case .adaptiveGradient:
            if let gradient = adaptiveGradient(opacity: configuration.tintOpacity) {
                gradient.draw(in: rect, angle: 0)
            } else if let colorInfo = averageColorInfo,
                      let color = NSColor(cgColor: colorInfo.color)?
                      .withAlphaComponent(configuration.tintOpacity)
            {
                // Use the average until the palette arrives to avoid an untinted flash.
                color.setFill()
                rect.fill()
            }
        }
    }

    /// Use the two dominant swatches, or nil before capture; repeated swatches produce a flat tint for single-colour wallpaper.
    private func adaptiveGradient(opacity: CGFloat) -> NSGradient? {
        guard
            let palette = wallpaperPalette,
            let primary = palette.primary,
            let secondary = palette.secondary
        else {
            return nil
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        guard
            let start = primary.cgColor(in: colorSpace),
            let end = secondary.cgColor(in: colorSpace),
            let startColor = NSColor(cgColor: start)?.withAlphaComponent(opacity),
            let endColor = NSColor(cgColor: end)?.withAlphaComponent(opacity)
        else {
            return nil
        }
        return NSGradient(starting: startColor, ending: endColor)
    }

    private var isBackgroundGlassActive = false

    /// Adds or removes the glass container on the panel based on background kind.
    private func updateBackgroundGlass() {
        guard let panel = window as? MenuBarOverlayPanel else { return }
        if configuration.backgroundKind == .glass {
            if isBackgroundGlassActive {
                if let glassView = panel.contentView?.subviews
                    .compactMap({ $0 as? NSGlassEffectView }).first
                {
                    updateBackgroundGlassSurface(glassView)
                }
                return
            }
            guard let realContent = panel.contentView else { return }
            isBackgroundGlassActive = true

            let container = NSView()
            container.wantsLayer = true

            let glassView = NSGlassEffectView()
            glassView.cornerRadius = 0
            glassView.translatesAutoresizingMaskIntoConstraints = false

            realContent.removeFromSuperview()
            realContent.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(glassView, positioned: .below, relativeTo: nil)
            container.addSubview(backgroundLiquidGlassView, positioned: .above, relativeTo: glassView)
            container.addSubview(realContent, positioned: .above, relativeTo: nil)
            panel.contentView = container

            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: container.topAnchor),
                glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glassView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),

                backgroundLiquidGlassView.topAnchor.constraint(equalTo: container.topAnchor),
                backgroundLiquidGlassView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                backgroundLiquidGlassView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                backgroundLiquidGlassView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),

                realContent.topAnchor.constraint(equalTo: container.topAnchor),
                realContent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                realContent.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                realContent.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            updateBackgroundGlassSurface(glassView)
        } else if isBackgroundGlassActive {
            isBackgroundGlassActive = false
            guard let container = panel.contentView,
                  let realContent = container.subviews
                  .compactMap({ $0 as? MenuBarOverlayPanelContentView }).first
            else { return }
            realContent.removeFromSuperview()
            panel.contentView = realContent
        }
    }

    private func updateBackgroundGlassSurface(_ glassView: NSGlassEffectView) {
        let style = configuration.backgroundGlassStyle
        if style.usesShapeAwareSurface {
            glassView.isHidden = true
            let glassBounds = CGRect(
                origin: .zero,
                size: CGSize(width: bounds.width, height: max(0, bounds.height - 5))
            )
            backgroundLiquidGlassView.update(
                path: CGPath(rect: glassBounds, transform: nil),
                isColored: configuration.backgroundGlassIsColored,
                tintColor: configuration.backgroundColor,
                tintOpacity: configuration.backgroundOpacity,
                effectOpacity: style.effectOpacity,
                usesDarkFade: style.usesDarkFade,
                borderColor: nil,
                borderWidth: 0
            )
            backgroundLiquidGlassView.isHidden = false
        } else {
            backgroundLiquidGlassView.isHidden = true
            configureGlassView(
                glassView,
                style: style,
                isColored: configuration.backgroundGlassIsColored,
                tintColor: configuration.backgroundColor,
                opacity: configuration.backgroundOpacity
            )
            glassView.isHidden = false
        }
    }

    private func configureGlassView(
        _ glassView: NSGlassEffectView,
        style: MenuBarGlassStyle,
        isColored: Bool,
        tintColor: CGColor,
        opacity: Double
    ) {
        glassView.style = style.nsGlassStyle
        glassView.tintColor = if style.usesTint, isColored {
            NSColor(cgColor: tintColor)?.withAlphaComponent(opacity)
        } else {
            nil
        }
    }

    /// Adds or removes the tint glass effect subview, masked to the shape path.
    private func updateTintGlass() {
        guard configuration.tintKind == .glass, let shapeCGPath else {
            tintGlassView.isHidden = true
            tintLiquidGlassView.isHidden = true
            tintGlassBorderLayer.isHidden = true
            return
        }

        let style = configuration.tintGlassStyle
        if style.usesShapeAwareSurface {
            if tintLiquidGlassView.superview == nil {
                addSubview(tintLiquidGlassView, positioned: .above, relativeTo: nil)
                NSLayoutConstraint.activate([
                    tintLiquidGlassView.topAnchor.constraint(equalTo: topAnchor),
                    tintLiquidGlassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    tintLiquidGlassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    tintLiquidGlassView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            }

            tintLiquidGlassView.update(
                path: shapeCGPath,
                isColored: configuration.tintGlassIsColored,
                tintColor: configuration.tintColor,
                tintOpacity: configuration.tintOpacity,
                effectOpacity: style.effectOpacity,
                usesDarkFade: style.usesDarkFade,
                borderColor: configuration.hasBorder ? configuration.borderColor : nil,
                borderWidth: configuration.borderWidth,
                borderStyle: configuration.borderStyle
            )
            tintGlassView.isHidden = true
            tintGlassBorderLayer.isHidden = true
            tintLiquidGlassView.isHidden = false
            return
        }

        tintLiquidGlassView.isHidden = true
        if tintGlassView.superview == nil {
            addSubview(tintGlassView, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                tintGlassView.topAnchor.constraint(equalTo: topAnchor),
                tintGlassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                tintGlassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                tintGlassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            tintGlassView.layer?.mask = tintGlassMaskLayer
            tintGlassView.contentView?.layer?.mask = tintGlassContentMaskLayer
            tintGlassView.contentView?.layer?.addSublayer(tintGlassBorderLayer)
        }
        tintGlassMaskLayer.path = shapeCGPath
        tintGlassContentMaskLayer.path = shapeCGPath
        configureGlassView(
            tintGlassView,
            style: style,
            isColored: configuration.tintGlassIsColored,
            tintColor: configuration.tintColor,
            opacity: configuration.tintOpacity
        )

        if configuration.hasBorder {
            tintGlassBorderLayer.path = shapeCGPath
            tintGlassBorderLayer.strokeColor = configuration.borderColor
            tintGlassBorderLayer.lineWidth = configuration.borderWidth * 2
            tintGlassBorderLayer.lineDashPattern = configuration.borderStyle
                .dashPattern(width: configuration.borderWidth)?.map { NSNumber(value: Double($0)) }
            tintGlassBorderLayer.isHidden = false
        } else {
            tintGlassBorderLayer.isHidden = true
        }

        tintGlassView.isHidden = false
    }

    /// Draws the background surrounding the shape in the given rectangle.
    private func drawBackground(in rect: CGRect) {
        switch configuration.backgroundKind {
        case .none:
            break
        case .solid:
            if let color = NSColor(cgColor: configuration.backgroundColor)?
                .withAlphaComponent(configuration.backgroundOpacity)
            {
                color.setFill()
                rect.fill()
            }
        case .gradient:
            if let gradient = configuration.backgroundGradient
                .withAlpha(configuration.backgroundOpacity)
                .nsGradient(using: .displayP3)
            {
                gradient.draw(in: rect, angle: 0)
            }
        case .glass:
            break
        case .adaptive:
            if let colorInfo = averageColorInfo,
               let color = NSColor(cgColor: colorInfo.color)?
               .withAlphaComponent(configuration.backgroundOpacity)
            {
                color.setFill()
                rect.fill()
            }
        }
    }

    /// Draws the background shadow at the top edge of the given rectangle.
    private func drawBackgroundShadow(in rect: CGRect) {
        guard configuration.backgroundHasShadow else { return }
        guard let gradient = NSGradient(
            colors: [
                NSColor(white: 0.0, alpha: 0.0),
                NSColor(white: 0.0, alpha: 0.2),
            ]
        ) else { return }
        let shadowBounds = CGRect(
            x: rect.minX,
            y: rect.minY - 5,
            width: rect.width,
            height: 5
        )
        gradient.draw(in: shadowBounds, angle: 90)
    }

    /// Draws the background border at the top edge of the given rectangle.
    private func drawBackgroundBorder(in rect: CGRect) {
        guard configuration.backgroundHasBorder else { return }
        guard let color = NSColor(cgColor: configuration.backgroundBorderColor) else { return }
        let borderBounds = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: configuration.backgroundBorderWidth
        )
        color.setFill()
        NSBezierPath(rect: borderBounds).fill()
    }

    override func draw(_: NSRect) {
        guard
            let overlayPanel,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let drawableBounds = getDrawableBounds()

        let shapePath =
            switch fullConfiguration.shapeKind {
            case .noShape:
                NSBezierPath(rect: drawableBounds)
            case .full:
                MenuBarShapePathBuilder.fullShapePath(
                    in: drawableBounds,
                    info: fullConfiguration.fullShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen,
                    leftMargin: fullConfiguration.leftMargin,
                    rightMargin: fullConfiguration.rightMargin,
                    insetAmount: overlayPanel.appState?.appearanceManager.menuBarInsetAmount
                )
            case .split:
                pathForSplitShape(
                    in: drawableBounds,
                    info: fullConfiguration.splitShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen
                )
            case .notch:
                MenuBarShapePathBuilder.notchShapePath(
                    in: drawableBounds,
                    info: fullConfiguration.notchShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen,
                    leftMargin: fullConfiguration.leftMargin,
                    rightMargin: fullConfiguration.rightMargin,
                    notchMargin: fullConfiguration.notchMargin,
                    insetAmount: overlayPanel.appState?.appearanceManager.menuBarInsetAmount
                )
            }

        shapeCGPath = shapePath.cgPath
        updateTintGlass()

        var hasBorder = false

        // Draw the full-area background behind shapes.
        drawBackground(in: drawableBounds)
        drawBackgroundShadow(in: drawableBounds)
        drawBackgroundBorder(in: drawableBounds)

        switch fullConfiguration.shapeKind {
        case .noShape:
            break
        case .full, .split, .notch:
            if configuration.hasShadow {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()

                shapePath.drawShadow(
                    color: .black.withAlphaComponent(0.5),
                    radius: 5
                )
            }

            if configuration.hasBorder, configuration.tintKind != .glass {
                hasBorder = true
            }

            do {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                shapePath.setClip()

                drawTint(in: drawableBounds)
            }

            if hasBorder,
               let borderColor = NSColor(cgColor: configuration.borderColor)
            {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let borderPath = shapePath

                borderPath.lineWidth = configuration.borderWidth * 2
                if let pattern = configuration.borderStyle.dashPattern(width: configuration.borderWidth) {
                    borderPath.setLineDash(pattern, count: pattern.count, phase: 0)
                }
                borderPath.setClip()

                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}
