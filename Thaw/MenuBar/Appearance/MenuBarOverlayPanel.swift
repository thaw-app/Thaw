//
//  MenuBarOverlayPanel.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import PlatformRuntimeKit
import ScreenCaptureKit

nonisolated enum MenuBarSplitPillGeometry {
    static func leadingBounds(
        applicationMenuFrame: CGRect,
        trailingContentMinX: CGFloat?,
        in rect: CGRect,
        screenFrame: CGRect,
        trailingPadding: CGFloat,
        leadingMargin: CGFloat,
        notchFrame: CGRect?,
        notchMargin: CGFloat
    ) -> CGRect {
        let screenOriginX = screenFrame.minX
        let leftX = rect.minX + leadingMargin
        var rightX = if applicationMenuFrame.width > 0 {
            applicationMenuFrame.maxX - screenOriginX + trailingPadding
        } else {
            rect.maxX
        }

        if let notchFrame {
            rightX = min(rightX, notchFrame.minX - screenOriginX - notchMargin)
        }
        if let trailingContentMinX {
            rightX = min(rightX, trailingContentMinX - screenOriginX - 4)
        }

        rightX = min(max(rightX, rect.minX), rect.maxX)
        return CGRect(
            x: leftX,
            y: rect.minY,
            width: max(0, rightX - leftX),
            height: rect.height
        )
    }

    static func trailingBounds(
        itemBounds: [CGRect],
        in rect: CGRect,
        screenFrame: CGRect,
        leadingOutset: CGFloat,
        trailingOutset: CGFloat,
        notchFrame: CGRect?,
        notchMargin: CGFloat
    ) -> CGRect {
        let displayItemBounds = itemBounds.filter { bounds in
            bounds.midX >= screenFrame.minX && bounds.midX <= screenFrame.maxX
        }
        guard
            let contentMinX = displayItemBounds.map(\.minX).min(),
            let contentMaxX = displayItemBounds.map(\.maxX).max()
        else { return .zero }

        let screenOriginX = screenFrame.minX
        var leftX = contentMinX - leadingOutset - screenOriginX
        var rightX = contentMaxX + trailingOutset - screenOriginX

        if let notchFrame {
            leftX = max(leftX, notchFrame.maxX - screenOriginX + notchMargin)
        }

        leftX = min(max(leftX, rect.minX), rect.maxX)
        rightX = min(max(rightX, rect.minX), rect.maxX)
        return CGRect(
            x: leftX,
            y: rect.minY,
            width: max(0, rightX - leftX),
            height: rect.height
        )
    }

    /// Section/reveal state used when deciding which AX frames belong in the
    /// split trailing pill.
    nonisolated struct TrailingPillContext {
        var revealedSection: MenuBarSection.Name?
        var section: (MenuBarItem) -> MenuBarSection.Name
    }

    /// Picks drawable split-pill rectangles, preferring the last stable pair
    /// only while geometry is frozen or when a fresh AX read is completely empty.
    static func resolveSplitPathBounds(
        leading: CGRect,
        trailing: CGRect,
        geometryFrozen: Bool,
        lastStableLeading: CGRect,
        lastStableTrailing: CGRect
    ) -> (leading: CGRect, trailing: CGRect, nextStableLeading: CGRect, nextStableTrailing: CGRect) {
        if geometryFrozen,
           lastStableLeading != .zero || lastStableTrailing != .zero
        {
            return (
                lastStableLeading,
                lastStableTrailing,
                lastStableLeading,
                lastStableTrailing
            )
        }

        let freshValid = leading != .zero
            && trailing != .zero
            && !leading.intersects(trailing)
        if freshValid {
            return (leading, trailing, leading, trailing)
        }

        if leading != .zero, trailing == .zero {
            return (leading, .zero, leading, .zero)
        }

        if leading != .zero, trailing != .zero, leading.intersects(trailing) {
            // Overlap during reflow: draw the leading segment only instead of
            // resurrecting a stale trailing pill that still spans empty space.
            return (leading, .zero, leading, .zero)
        }

        if leading == .zero, trailing == .zero,
           lastStableLeading != .zero,
           lastStableTrailing != .zero,
           !lastStableLeading.intersects(lastStableTrailing)
        {
            return (
                lastStableLeading,
                lastStableTrailing,
                lastStableLeading,
                lastStableTrailing
            )
        }

        if leading == .zero, trailing == .zero,
           lastStableLeading != .zero,
           lastStableTrailing == .zero
        {
            return (lastStableLeading, .zero, lastStableLeading, .zero)
        }

        return (leading, trailing, lastStableLeading, lastStableTrailing)
    }

    /// Bounds that the split trailing pill should wrap on macOS 27.
    @available(macOS 27, *)
    static func trailingPillBounds(
        from items: [MenuBarItem],
        context: TrailingPillContext
    ) -> [CGRect] {
        let isRevealingHidden = context.revealedSection == .hidden
            || context.revealedSection == .alwaysHidden
        let isRevealingAlwaysHidden = context.revealedSection == .alwaysHidden

        return items.compactMap { item -> CGRect? in
            guard shouldIncludeItemInTrailingPill(
                item,
                among: items,
                context: context,
                isRevealingHidden: isRevealingHidden,
                isRevealingAlwaysHidden: isRevealingAlwaysHidden
            ) else {
                return nil
            }
            return item.bounds
        }
    }

    /// Adds approximate bounds for a visible runtime status item that does not
    /// vend an AX child. The appearance overlay needs its physical span, but
    /// the item must remain absent from Thaw's management and layout models.
    @MainActor
    @available(macOS 27, *)
    static func opaqueVisibleBounds(
        from items: [MenuBarItem],
        positions: [String: Int],
        keys: [String]
    ) -> [CGRect] {
        let existingKeys = Array(positions.keys)
        let references: [(bounds: CGRect, weight: Int)] = items.compactMap { item in
            guard item.isOnScreen,
                  !item.bounds.isEmpty,
                  let key = RuntimePositionStore.resolveKey(
                      for: item,
                      existingKeys: existingKeys,
                      positions: positions,
                      liveItems: items
                  ),
                  let weight = positions[key]
            else {
                return nil
            }
            return (item.bounds, weight)
        }
        guard references.count > 1 else { return [] }

        let byX = references.sorted { $0.bounds.midX < $1.bounds.midX }
        let ascending = (byX.first?.weight ?? 0) < (byX.last?.weight ?? 0)
        let visualOrder = references.sorted {
            ascending ? $0.weight < $1.weight : $0.weight > $1.weight
        }
        let fallbackWidth = max(20, references.map(\.bounds.width).reduce(0, +) / CGFloat(references.count))

        return keys.compactMap { key in
            guard let weight = positions[key] else { return nil }
            let insertion = visualOrder.firstIndex { reference in
                ascending ? weight < reference.weight : weight > reference.weight
            } ?? visualOrder.endIndex
            let before = insertion > visualOrder.startIndex ? visualOrder[insertion - 1].bounds : nil
            let after = insertion < visualOrder.endIndex ? visualOrder[insertion].bounds : nil

            let x: CGFloat
            let width: CGFloat
            switch (before, after) {
            case let (before?, after?):
                // An AX-opaque item occupies the whole gap its neighbouring
                // status items leave in the live bar. Using an average icon
                // width here only covers half of wider items such as Little
                // Snitch's traffic meter.
                x = before.maxX + 4
                width = max(20, after.minX - before.maxX - 8)
            case let (before?, nil):
                x = before.maxX + 4
                width = fallbackWidth
            case let (nil, after?):
                width = fallbackWidth
                x = after.minX - width - 4
            case (nil, nil):
                return nil
            }
            return CGRect(x: x, y: byX[0].bounds.minY, width: width, height: byX[0].bounds.height)
        }
    }

    /// Whether a live status item should contribute to the split trailing pill.
    @available(macOS 27, *)
    static func shouldIncludeItemInTrailingPill(
        _ item: MenuBarItem,
        among peers: [MenuBarItem],
        context: TrailingPillContext,
        isRevealingHidden: Bool,
        isRevealingAlwaysHidden: Bool
    ) -> Bool {
        let isHiddenSectionDivider = item.isControlItem
            && !item.tag.matchesVisibleControlItem
        guard !item.isSystemClone,
              !isHiddenSectionDivider,
              item.isOnScreen,
              !item.bounds.isEmpty,
              !item.isParkedOffMenuBarBand(among: peers)
        else {
            return false
        }

        if isRevealingHidden {
            if item.tag.matchesVisibleControlItem {
                return true
            }
            if context.section(item) == .alwaysHidden, !isRevealingAlwaysHidden {
                return false
            }
            return true
        }

        // CC-governable items (Sound, WiFi, …) can be in the hidden section when
        // CC-hidden; their AX position is then in the hidden slot (far left). Exclude
        // them like any other non-visible item so the trailing pill doesn't stretch
        // over empty space. Truly non-concealable items (Spotlight, Clock, …) are
        // forcedVisible and always resolve to .visible here.
        if context.section(item) != .visible {
            return false
        }
        return true
    }
}

// MARK: - Overlay Panel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
///
/// Constructed only from `MenuBarAppearanceManager` (`@MainActor`), and has
/// no `nonisolated` members of its own, so it is main-actor-confined like
/// every other `NSPanel` subclass; `@MainActor` makes it implicitly
/// `Sendable` without an `@unchecked` escape hatch.
@MainActor
final class MenuBarOverlayPanel: NSPanel {
    private let diagLog = DiagLog(category: "MenuBarOverlayPanel")
    /// Flags representing the updatable components of a panel.
    enum UpdateFlag: String, CustomStringConvertible {
        case applicationMenuFrame

        var description: String {
            rawValue
        }
    }

    /// The kind of validation that occurs before an update.
    private enum ValidationKind {
        case showing
        case updates
    }

    /// A context that manages panel update tasks.
    private final class UpdateTaskContext {
        private var tasks = [UpdateFlag: Task<Void, any Error>]()

        /// Sets the task for the given update flag.
        ///
        /// Setting the task cancels the previous task for the flag, if there is one.
        ///
        /// - Parameters:
        ///   - flag: The update flag to set the task for.
        ///   - timeout: The timeout of the task.
        ///   - operation: The operation for the task to perform.
        func setTask(
            for flag: UpdateFlag,
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> Void
        ) {
            cancelTask(for: flag)
            tasks[flag] = Self.runWithTimeout(timeout: timeout, operation: operation)
        }

        private static func runWithTimeout(
            timeout: Duration,
            operation: @escaping @Sendable () async throws -> Void
        ) -> Task<Void, Error> {
            Task {
                try await operation()
                try? await Task.sleep(for: timeout)
            }
        }

        /// Cancels the task for the given update flag.
        ///
        /// - Parameter flag: The update flag to cancel the task for.
        func cancelTask(for flag: UpdateFlag) {
            tasks.removeValue(forKey: flag)?.cancel()
        }

        /// Cancels all tasks.
        func cancelAllTasks() {
            for task in tasks.values {
                task.cancel()
            }
            tasks.removeAll()
        }
    }

    /// A Boolean value that indicates whether the panel needs to be shown.
    @Published var needsShow = false

    /// A Boolean value that indicates whether Mission Control or App Expose is active.
    @Published private var isMissionControlActive = false

    /// Flags representing the components of the panel currently in need of an update.
    @Published private(set) var updateFlags = Set<UpdateFlag>()

    /// The frame of the application menu.
    @Published private(set) var applicationMenuFrame: CGRect?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

    /// Retry task for show() when it fails due to unsettled Window Server.
    private var showRetryTask: Task<Void, Never>?

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// A tiny invisible window used to detect Mission Control.
    ///
    /// This window is NOT stationary, so it moves during Mission Control.
    /// By comparing its actual on-screen position with its intended position,
    /// we can reliably detect if Mission Control is active.
    private lazy var missionControlProbeWindow: NSPanel = {
        let window = NSPanel(
            contentRect: CGRect(x: owningScreen.frame.midX, y: owningScreen.frame.midY, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.alphaValue = 0.0
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
        // Specifically NOT .stationary or .transient to allow movement.
        // .ignoresCycle and .fullScreenAuxiliary help hide the 'Thaw' label.
        window.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        // Low enough for Mission Control to arrange (both axes move).
        // Positioned at screen center so MC grid displaces it in both x and y.
        window.level = .floating
        return window
    }()

    /// The origin of the probe window when it is at rest (not in Mission Control).
    private var probeAtRestOrigin: CGPoint?

    /// The time when the probe window first became displaced.
    private var missionControlDisplacedSince: Date?

    private var shouldPollMissionControlProbe: Bool {
        // Keep polling while `isMissionControlActive` is set: this poll is the
        // only path that can clear the flag when no space change fires.
        // "Click wallpaper to reveal desktop" displaces the probe window just
        // like Mission Control but never changes the active space, so gating
        // purely on visibility left the panel wedged at alpha 0 (border and
        // tint gone) until relaunch (#687).
        appState != nil && (alphaValue > 0 || isMissionControlActive)
    }

    /// Creates an overlay panel with the given app state and owning screen.
    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
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
        self.collectionBehavior = [
            .fullScreenNone, .ignoresCycle, .stationary,
        ]
        self.contentView = MenuBarOverlayPanelContentView()
        configureCancellables()

        missionControlProbeWindow.orderFrontRegardless()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Show the panel on the active space.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isMissionControlActive = false
                self?.needsShow = true
            }
            .store(in: &c)

        // Poll the mission control probe window to detect if it has moved/scaled.
        Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard shouldPollMissionControlProbe else { return }
                let windowID = CGWindowID(self.missionControlProbeWindow.windowNumber)
                if let actualBounds = Bridging.getWindowBounds(for: windowID) {
                    let actualOrigin = actualBounds.origin

                    // Capture the "at-rest" origin when we're reasonably sure we're not in Mission Control
                    if self.probeAtRestOrigin == nil {
                        self.probeAtRestOrigin = actualOrigin
                        return
                    }

                    guard let atRest = self.probeAtRestOrigin else { return }

                    let isActive = abs(actualOrigin.x - atRest.x) > 1.0 &&
                        abs(actualOrigin.y - atRest.y) > 1.0

                    let now = Date()

                    if isActive {
                        if let displacedSince = self.missionControlDisplacedSince {
                            if now.timeIntervalSince(displacedSince) > 0.1 {
                                self.isMissionControlActive = true
                            }
                        } else {
                            self.missionControlDisplacedSince = now
                        }
                    } else {
                        self.missionControlDisplacedSince = nil
                        self.isMissionControlActive = false
                    }
                }
            }
            .store(in: &c)

        // Update application menu frame when the menu bar owning or frontmost app changes.
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
            guard let self else {
                return
            }
            updateTaskContext.setTask(
                for: .applicationMenuFrame,
                timeout: .seconds(10)
            ) { @MainActor [weak self] in
                var candidate: CGRect?
                var settledCount = 0
                for i in 0 ..< 10 {
                    do {
                        try Task.checkCancellation()
                    } catch {
                        return
                    }
                    guard let self else { return }
                    let latest = self.owningScreen
                        .getApplicationMenuFrame(bypassCache: true)
                    guard let latest else { continue }
                    let isFirst = i == 0
                    var changed = true
                    if let c = candidate {
                        changed = latest != c
                    }
                    if isFirst || changed {
                        self.applicationMenuFrame = latest
                        candidate = latest
                        settledCount = 0
                    } else {
                        settledCount += 1
                        if settledCount >= 3 {
                            return
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                if self.owningScreen != NSScreen.main {
                    self.updateTaskContext.cancelTask(
                        for: .applicationMenuFrame
                    )
                }
            }
        }
        .store(in: &c)

        // Special cases for when the user drags an app onto or clicks into another space.
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
            self?.insertUpdateFlag(.applicationMenuFrame)
        }
        .store(in: &c)

        Timer.publish(every: 60, tolerance: 10, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isOnActiveSpace else {
                    return
                }
                self.insertUpdateFlag(.applicationMenuFrame)
            }
            .store(in: &c)

        $needsShow
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] needsShow in
                guard let self, needsShow else {
                    return
                }
                defer {
                    self.needsShow = false
                }
                show()
            }
            .store(in: &c)

        $updateFlags
            .sink { [weak self] flags in
                guard let self, !flags.isEmpty else {
                    return
                }
                Task {
                    // Must be run async, or this will not remove the flags.
                    self.updateFlags.removeAll()
                }
                let windows = WindowInfo.createWindows(option: .onScreen)
                if validate(for: .updates, with: windows) {
                    performUpdates(
                        for: flags,
                        windows: windows,
                        screen: owningScreen
                    )
                }
            }
            .store(in: &c)

        if let appState {
            Publishers.CombineLatest(
                appState.menuBarManager.$isMenuBarHiddenBySystem,
                $isMissionControlActive
            )
            .sink { [weak self] isMenuBarHidden, isMissionControlActive in
                let isHidden = isMenuBarHidden || isMissionControlActive
                self?.alphaValue = isHidden ? 0 : 1
            }
            .store(in: &c)

            appState.appearanceManager.$configuration
                .sink { [weak self] _ in
                    self?.updateWindowLevel()
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Inserts the given update flag into the panel's current list of update flags.
    func insertUpdateFlag(_ flag: UpdateFlag) {
        updateFlags.insert(flag)
    }

    /// Performs validation for the given validation kind. Returns the panel's
    /// owning display if successful. Returns `nil` on failure.
    private func validate(for kind: ValidationKind, with windows: [WindowInfo])
        -> Bool
    {
        lazy var actionMessage =
            switch kind {
            case .showing: "Preventing overlay panel from showing."
            case .updates: "Preventing overlay panel from updating."
            }
        guard let appState else {
            diagLog.debug("No app state. \(actionMessage)")
            return false
        }
        guard
            appState.menuBarManager.hasValidMenuBar(
                in: windows,
                for: owningScreen.displayID
            )
        else {
            diagLog.debug("No valid menu bar found. \(actionMessage)")
            return false
        }
        return true
    }

    /// Stores the frame of the menu bar's application menu.
    private func updateApplicationMenuFrame(for screen: NSScreen) {
        guard
            let menuBarManager = appState?.menuBarManager,
            !menuBarManager.isMenuBarHiddenBySystem
        else {
            return
        }
        applicationMenuFrame = screen.getApplicationMenuFrame()
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(
        for flags: Set<UpdateFlag>,
        windows _: [WindowInfo],
        screen: NSScreen
    ) {
        if flags.contains(.applicationMenuFrame) {
            updateApplicationMenuFrame(for: screen)
        }
    }

    /// Shows the panel.
    private func show() {
        guard let appState else {
            return
        }

        guard appState.appearanceManager.overlayPanels.contains(self) else {
            diagLog.warning("Overlay panel \(self) not retained")
            return
        }

        // Validate before showing to ensure panel should be visible on this screen.
        let windows = WindowInfo.createWindows(option: .onScreen)
        guard validate(for: .showing, with: windows) else {
            scheduleShowRetry()
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

        updateFlags = [.applicationMenuFrame]

        if !appState.menuBarManager.isMenuBarHiddenBySystem {
            alphaValue = 1
        }
    }

    /// Schedules a retry of show() after a delay when validation or
    /// menu bar height was not available (e.g. during a display change
    /// before the Window Server has settled). Only the latest retry
    /// is kept; cancelled if show() succeeds in the meantime.
    private func scheduleShowRetry() {
        showRetryTask?.cancel()
        showRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.needsShow = true }
        }
    }

    /// Workaround to release owningScreen reference since it's a let constant
    /// We can't change owningScreen to var because it's used throughout the panel,
    /// but we can clear other references to help with deallocation
    private func cleanupReferences() {
        // Clear all published state to release retained objects
        applicationMenuFrame = nil
        updateFlags.removeAll()
        probeAtRestOrigin = nil
    }

    override func close() {
        showRetryTask?.cancel()
        showRetryTask = nil
        // Cancel all pending update tasks to prevent memory leaks
        updateTaskContext.cancelAllTasks()
        // Clear publishers to release references
        cancellables.removeAll()
        // Clear captured wallpaper image and other state
        cleanupReferences()
        // Release content view
        contentView = nil
        // Close the mission control probe window
        missionControlProbeWindow.close()
        super.close()
        #if DEBUG
            diagLog.debug("Overlay panel closed. Active windows: \(NSApplication.shared.windows.count)")
        #endif
    }

    /// Moves the panel behind the menu bar whenever a tint or shape is active
    /// so the menu bar's own blur blends the content and items stay crisp.
    private func updateWindowLevel() {
        guard let appState else { return }
        let config = appState.appearanceManager.configuration
        if config.current.tintKind != .noTint || config.shapeKind != .noShape || config.current.backgroundKind != .none {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
        } else {
            level = .statusBar
        }
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

    private var cancellables = Set<AnyCancellable>()

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

    /// Cached menu bar item windows, updated by publishers instead of
    /// being queried synchronously during each `draw(_:)` call.
    private var cachedItemWindows: [WindowInfo] = []

    /// Physical status-item bounds used by the split trailing pill on macOS 27.
    /// The logical item-cache sections cannot be used for this: Apple items can
    /// remain physically visible while assigned Hidden, and concealed-item
    /// snapshots can retain stale on-screen bounds. A fresh AXExtrasMenuBar walk
    /// is the source of truth for what the pill must wrap.
    private var cachedAXItemBounds: [CGRect] = []

    /// The Thaw chevron's AX frame while concealed, kept separately from
    /// ``cachedAXItemBounds`` rather than folded into it. That shared array
    /// also feeds `computeLeadingPathBounds`'s `trailingContentMinX` clamp;
    /// appending the chevron there once pulled the clamp far left and painted
    /// over real status items (the leading pill's "cutout" shrank). Used only
    /// to widen the trailing pill's own bounds so it wraps the chevron too.
    /// `.zero` while revealing Hidden, where the chevron is already a normal
    /// candidate in `cachedAXItemBounds`.
    private var cachedChevronFrame: CGRect = .zero

    /// Last successfully drawn split-pill rectangles. Used while geometry is
    /// frozen or when a transitional AX read would intersect / fall back to full.
    private var lastStableLeadingPathBounds: CGRect = .zero
    private var lastStableTrailingPathBounds: CGRect = .zero

    /// When true, ``pathForSplitShape`` keeps drawing ``lastStableLeadingPathBounds``
    /// and ``lastStableTrailingPathBounds`` until the pending AX refresh finishes.
    private var splitPillGeometryFrozen = false

    /// Debounces AX geometry refreshes while MenuBarAgent is reflowing items.
    private var axItemBoundsRefreshTask: Task<Void, Never>?

    /// Delay for the in-flight or next AX bounds refresh.
    private var axItemBoundsRefreshDelay: Duration = .milliseconds(200)

    /// Incremented on every ``scheduleAXItemBoundsRefresh(delay:)`` call so a
    /// superseded task can recognize it's stale after being cancelled. Without
    /// this, a cancelled task's cleanup (clearing ``axItemBoundsRefreshTask``
    /// and ``splitPillGeometryFrozen``) can run *after* a newer call has
    /// already installed its own task, wiping out that newer task's state and
    /// silently defeating the debounce.
    private var axItemBoundsRefreshGeneration = 0

    /// In-flight confirmation task for settling the trailing item-window cache
    /// after an app switch. Cancelled and replaced whenever a new
    /// applicationMenuFrame value arrives so that only the latest app's icon
    /// layout is committed.
    private var itemWindowsConfirmTask: Task<Void, Never>?

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The currently displayed configuration.
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
        var c = Set<AnyCancellable>()

        if let overlayPanel {
            if let appState = overlayPanel.appState {
                appState.appearanceManager.$configuration
                    .sink { [weak self] config in
                        self?.fullConfiguration = config
                    }
                    .store(in: &c)

                appState.appearanceManager.objectWillChange
                    .debounce(for: .seconds(0), scheduler: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else { return }
                        fullConfiguration = appState.appearanceManager.configuration
                    }
                    .store(in: &c)

                appState.appearanceManager.$previewConfiguration
                    .removeDuplicates()
                    .assign(to: &$previewConfiguration)

                appState.menuBarManager.$averageColors
                    .sink { [weak self] colors in
                        guard let self, let displayID = self.overlayPanel?.owningScreen.displayID else { return }
                        self.averageColorInfo = colors[displayID]
                    }
                    .store(in: &c)

                // Fade out whenever a menu bar item is being dragged.
                appState.$isDraggingMenuBarItem
                    .removeDuplicates()
                    .sink { [weak self] isDragging in
                        if isDragging {
                            self?.animator().alphaValue = 0
                        } else {
                            self?.animator().alphaValue = 1
                        }
                    }
                    .store(in: &c)

                for section in appState.menuBarManager.sections {
                    // Redraw whenever the window frame of a control item changes.
                    //
                    // - NOTE: A previous attempt was made to redraw the view when the
                    //   section's `isHidden` property was changed. This would be semantically
                    //   ideal, but the property sometimes changes before the menu bar items
                    //   are actually updated on-screen. Since the view's drawing process relies
                    //   on getting an accurate position of each menu bar item, we need to use
                    //   something that publishes its changes only after the items are updated.
                    section.controlItem.$onScreenFrame
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            self?.updateCachedItemWindows()
                            if #available(macOS 27, *) {
                                // Freeze while the bar re-settles so a
                                // transient AX read doesn't flash wrong bounds.
                                self?.splitPillGeometryFrozen = true
                                self?.scheduleAXItemBoundsRefresh()
                            } else {
                                self?.needsDisplay = true
                            }
                        }
                        .store(in: &c)
                }

                // macOS 27: refresh the split pill from physical AX geometry after
                // the item cache has been published. `objectWillChange` fires before
                // assignment and used to redraw from stale/partial section buckets.
                if #available(macOS 27, *) {
                    appState.itemManager.$itemCache
                        .removeDuplicates()
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            // Freeze so a transient AX read during the
                            // cache-change reflow doesn't flash wrong bounds.
                            self?.splitPillGeometryFrozen = true
                            self?.scheduleAXItemBoundsRefresh()
                        }
                        .store(in: &c)

                    appState.menuBarManager.sectionController?.$revealedSection
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] revealed in
                            guard let self else { return }
                            // Hold the last stable split shape while MenuBarAgent
                            // reflows; intermediate AX reads intersect or go empty
                            // and flash a full-width fallback pill.
                            splitPillGeometryFrozen = true
                            needsDisplay = true
                            let delay: Duration = revealed == nil
                                ? .milliseconds(350)
                                : .milliseconds(200)
                            scheduleAXItemBoundsRefresh(delay: delay)
                        }
                        .store(in: &c)
                }
            }

            // Redraw whenever the application menu frame changes.
            // Also refresh cached item windows to pick up items added/removed
            // by other apps (e.g. status bar icons appearing or disappearing).
            //
            // The item windows are re-read with a two-read confirmation loop
            // (mirroring the AX confirmation used for applicationMenuFrame) so
            // that we never commit a transitional Window Server layout. The
            // trailing shape shadow artefact on app-switch was caused by
            // calling updateCachedItemWindows() synchronously here, before the
            // icon windows had settled into their new positions.
            overlayPanel.$applicationMenuFrame
                .sink { [weak self] _ in
                    guard let self, let screen = self.overlayPanel?.owningScreen else { return }
                    self.scheduleItemWindowsConfirmation(for: screen)
                }
                .store(in: &c)
        }

        // Redraw whenever the configurations or average color change.
        $fullConfiguration.replace(with: ())
            .merge(with: $previewConfiguration.replace(with: ()))
            .merge(with: $averageColorInfo.replace(with: ()))
            .sink { [weak self] _ in
                self?.updateBackgroundGlass()
                self?.needsDisplay = true
            }
            .store(in: &c)

        cancellables = c

        // Populate the cache immediately so the first draw has data.
        updateCachedItemWindows()
        if #available(macOS 27, *) {
            scheduleAXItemBoundsRefresh(delay: .zero)
        }
    }

    /// Refreshes the physical macOS 27 status-item span after MenuBarAgent has
    /// settled. Repeated cache/frame/reveal events cancel the prior task, so a
    /// reordering burst costs one AX walk and publishes one final redraw.
    @available(macOS 27, *)
    private func scheduleAXItemBoundsRefresh(
        delay: Duration = .milliseconds(200)
    ) {
        axItemBoundsRefreshDelay = delay
        axItemBoundsRefreshTask?.cancel()
        axItemBoundsRefreshTask = nil
        axItemBoundsRefreshGeneration += 1
        let generation = axItemBoundsRefreshGeneration

        guard let displayID = overlayPanel?.owningScreen.displayID else {
            cachedAXItemBounds = []
            splitPillGeometryFrozen = false
            needsDisplay = true
            return
        }

        axItemBoundsRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // Only clear state if a newer call hasn't already superseded
                // this task — otherwise this cancelled task's cleanup would
                // stomp on the newer task's in-flight state.
                if generation == axItemBoundsRefreshGeneration {
                    splitPillGeometryFrozen = false
                    axItemBoundsRefreshTask = nil
                }
                needsDisplay = true
            }

            try? await Task.sleep(for: axItemBoundsRefreshDelay)
            guard !Task.isCancelled else { return }

            let displayBounds = CGDisplayBounds(displayID)
            let (recentItems, recentAt) = overlayPanel?.appState?.itemManager.lastOnScreenMenuBarItems ?? ([], nil)
            let items: [MenuBarItem] = if let recentAt, recentAt.duration(to: .now) < .milliseconds(200) {
                recentItems.filter { $0.bounds.intersects(displayBounds) }
            } else {
                await MenuBarItem.getMenuBarItems(
                    on: displayID,
                    option: [.onScreen, .activeSpace]
                )
            }
            guard !Task.isCancelled else { return }

            let controller = overlayPanel?.appState?.menuBarManager.sectionController
            let context = MenuBarSplitPillGeometry.TrailingPillContext(
                revealedSection: controller?.revealedSection,
                section: { item in
                    controller?.section(for: item) ?? .visible
                }
            )
            let bounds = MenuBarSplitPillGeometry.trailingPillBounds(
                from: items,
                context: context
            )
            let opaqueBounds = MenuBarSplitPillGeometry.opaqueVisibleBounds(
                from: items,
                positions: RuntimePositionStore.currentPositions(),
                keys: NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier == "at.obdev.littlesnitch.agent"
                } ? ["status:at.obdev.littlesnitch.agent::Item-0"] : []
            )
            cachedAXItemBounds = bounds + opaqueBounds
            let isRevealingHidden = controller?.revealedSection == .hidden
                || controller?.revealedSection == .alwaysHidden
            cachedChevronFrame = isRevealingHidden
                ? .zero
                : (items.first(where: { $0.tag.matchesVisibleControlItem })?.bounds ?? .zero)
        }
    }

    /// Refreshes the cached menu bar item windows from the Window Server.
    ///
    /// Calling this directly (e.g. from the controlItem frame-change path)
    /// cancels any in-flight confirmation task so that a fresh synchronous read
    /// always wins over a stale async one.
    private func updateCachedItemWindows() {
        itemWindowsConfirmTask?.cancel()
        itemWindowsConfirmTask = nil
        guard let screen = overlayPanel?.owningScreen else {
            cachedItemWindows = []
            return
        }
        // macOS 27: status items are not enumerable as CGS windows, so this
        // always returns []. Skip the dead CGS calls (and their log spam) and
        // set [] directly — behavior-identical, just without the round-trips.
        if #available(macOS 27, *) {
            cachedItemWindows = []
            return
        }
        cachedItemWindows = MenuBarItem.getMenuBarItemWindows(
            on: screen.displayID,
            option: .onScreen
        )
    }

    /// Starts an async confirmation task that re-reads menu bar item windows
    /// until two consecutive reads return the same total width, then commits
    /// the result. This mirrors the two-read AX confirmation used for
    /// `applicationMenuFrame` and prevents the trailing shape from being drawn
    /// with a stale (transitional) icon layout immediately after an app switch.
    private func scheduleItemWindowsConfirmation(for screen: NSScreen) {
        // macOS 27: item windows aren't enumerable (always []), so the
        // confirmation poll can never produce data — skip it to avoid 10 dead
        // CGS reads (and their log spam) per app switch.
        if #available(macOS 27, *) {
            itemWindowsConfirmTask?.cancel()
            itemWindowsConfirmTask = nil
            cachedItemWindows = []
            needsDisplay = true
            scheduleAXItemBoundsRefresh()
            return
        }
        // Hoist displayID before entering the Task so that no AppKit
        // (NSScreen) access occurs off the main thread.
        let displayID = screen.displayID
        itemWindowsConfirmTask?.cancel()
        itemWindowsConfirmTask = Task { [weak self] in
            guard let self else { return }
            var candidate: [WindowInfo]?
            var candidateWidth: CGFloat = 0
            var settledCount = 0
            for i in 0 ..< 10 {
                guard !Task.isCancelled else { return }
                let latest = MenuBarItem.getMenuBarItemWindows(
                    on: displayID,
                    option: .onScreen
                )
                let latestWidth = latest.reduce(0) { $0 + $1.bounds.width }

                if i == 0 || abs(latestWidth - candidateWidth) >= 1 {
                    // First read or width changed — commit immediately.
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.cachedItemWindows = latest
                        self.needsDisplay = true
                    }
                    candidate = latest
                    candidateWidth = latestWidth
                    settledCount = 0
                } else {
                    settledCount += 1
                    if settledCount >= 3 {
                        // Stable for 2 consecutive reads — done.
                        return
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            // Exhausted retries — commit last value if not already settled.
            if let candidate {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.cachedItemWindows = candidate
                    self.needsDisplay = true
                }
            }
        }
    }

    /// Returns a path in the given rectangle, with the given end caps,
    /// and inset by the given amounts.
    private func shapePath(
        in rect: CGRect,
        leadingEndCap: MenuBarEndCap,
        trailingEndCap: MenuBarEndCap,
        screen: NSScreen
    ) -> NSBezierPath {
        let insetRect: CGRect =
            if !screen.hasNotch {
                switch (leadingEndCap, trailingEndCap) {
                case (.square, .square):
                    CGRect(
                        x: rect.origin.x,
                        y: rect.origin.y + 1,
                        width: rect.width,
                        height: rect.height - 2
                    )
                case (.square, .round):
                    CGRect(
                        x: rect.origin.x,
                        y: rect.origin.y + 1,
                        width: rect.width - 1,
                        height: rect.height - 2
                    )
                case (.round, .square):
                    CGRect(
                        x: rect.origin.x + 1,
                        y: rect.origin.y + 1,
                        width: rect.width - 1,
                        height: rect.height - 2
                    )
                case (.round, .round):
                    CGRect(
                        x: rect.origin.x + 1,
                        y: rect.origin.y + 1,
                        width: rect.width - 2,
                        height: rect.height - 2
                    )
                }
            } else {
                rect
            }

        let shapeBounds = CGRect(
            x: insetRect.minX + insetRect.height / 2,
            y: insetRect.minY,
            width: insetRect.width - insetRect.height,
            height: insetRect.height
        )
        let leadingEndCapBounds = CGRect(
            x: insetRect.minX,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )
        let trailingEndCapBounds = CGRect(
            x: insetRect.maxX - insetRect.height,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )

        var path = NSBezierPath(rect: shapeBounds)

        path =
            switch leadingEndCap {
            case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

        path =
            switch trailingEndCap {
            case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/notch`` shape kind.
    /// Behaves like full on non-notched displays, splits at the notch
    /// on notched displays.
    private func pathForNotchShape(
        in rect: CGRect,
        info: MenuBarNotchShapeInfo,
        isInset: Bool,
        screen: NSScreen
    ) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager
        else {
            return NSBezierPath()
        }

        // Non-notched: behaves like full shape using the outer end caps
        guard screen.hasNotch,
              let topLeft = screen.auxiliaryTopLeftArea,
              let topRight = screen.auxiliaryTopRightArea
        else {
            let fullInfo = MenuBarFullShapeInfo(
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap
            )
            return pathForFullShape(in: rect, info: fullInfo, isInset: isInset, screen: screen)
        }

        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }

        let screenOrigin = screen.frame.minX

        let notchMargin = fullConfiguration.notchMargin

        let leadingBounds: CGRect = {
            let notchLeftX = topLeft.maxX - screenOrigin - notchMargin
            let adjustedMinX = rect.minX + fullConfiguration.leftMargin
            let width = max(0, notchLeftX - adjustedMinX)
            return CGRect(x: adjustedMinX, y: rect.minY, width: width, height: rect.height)
        }()

        let trailingBounds: CGRect = {
            let notchRightX = topRight.minX - screenOrigin + notchMargin
            let maxX = rect.maxX - fullConfiguration.rightMargin
            let width = max(0, maxX - notchRightX)
            return CGRect(x: notchRightX, y: rect.minY, width: width, height: rect.height)
        }()

        if leadingBounds.width <= 0 || trailingBounds.width <= 0
            || leadingBounds.intersects(trailingBounds)
        {
            let fullInfo = MenuBarFullShapeInfo(
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap
            )
            return pathForFullShape(in: rect, info: fullInfo, isInset: isInset, screen: screen)
        }

        let leadingPath = shapePath(
            in: leadingBounds,
            leadingEndCap: info.leading.leadingEndCap,
            trailingEndCap: info.leading.trailingEndCap,
            screen: screen
        )

        let trailingPath = shapePath(
            in: trailingBounds,
            leadingEndCap: info.trailing.leadingEndCap,
            trailingEndCap: info.trailing.trailingEndCap,
            screen: screen
        )

        let path = NSBezierPath()
        path.append(leadingPath)
        path.append(trailingPath)
        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/full`` shape kind.
    private func pathForFullShape(
        in rect: CGRect,
        info: MenuBarFullShapeInfo,
        isInset: Bool,
        screen: NSScreen
    ) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager
        else {
            return NSBezierPath()
        }
        var rect = rect
        rect.origin.x += fullConfiguration.leftMargin
        rect.size.width -= (fullConfiguration.leftMargin + fullConfiguration.rightMargin)

        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        return shapePath(
            in: rect,
            leadingEndCap: info.leadingEndCap,
            trailingEndCap: info.trailingEndCap,
            screen: screen
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    /// The bounds of the trailing status items the split trailing pill wraps.
    ///
    /// macOS ≤26 sources these from real CGS item windows (``cachedItemWindows``).
    /// macOS 27 status items have no CGS windows, so use a debounced physical AX
    /// snapshot. This deliberately ignores logical section assignment: Apple
    /// items assigned Hidden can remain on screen, while concealed-item snapshots
    /// can retain stale bounds. The pill must wrap what is physically present.
    private func trailingContentItemBounds() -> [CGRect] {
        if #available(macOS 27, *) {
            return cachedAXItemBounds
        }
        return cachedItemWindows.map(\.bounds)
    }

    /// Computes the leading pill rectangle from the application menu frame.
    ///
    /// The legacy offset-based width formula double-counted overlay origin
    /// coordinates and could leave a wide empty shelf inside the pill. Cap the
    /// trailing edge at the first status item so macOS 27 menu-bar unions that
    /// swallow the status area do not stretch the leading pill.
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
            if #available(macOS 27, *) {
                return 12
            }
            return 20
        }()

        return MenuBarSplitPillGeometry.leadingBounds(
            applicationMenuFrame: applicationMenuFrame,
            trailingContentMinX: trailingContentMinX,
            in: rect,
            screenFrame: screen.frame,
            trailingPadding: trailingPadding,
            leadingMargin: fullConfiguration.leftMargin,
            notchFrame: screen.frameOfNotch,
            notchMargin: fullConfiguration.notchMargin
        )
    }

    /// Computes the trailing pill rectangle from the union of item bounds.
    ///
    /// Summing individual widths underestimates the span whenever icons have
    /// gaps between them, which leaves the leftmost items outside the pill.
    private func computeTrailingPathBounds(
        itemBounds: [CGRect],
        in rect: CGRect,
        shouldInset: Bool,
        trailingEndCap: MenuBarEndCap,
        screen: NSScreen,
        appearanceManager: MenuBarAppearanceManager
    ) -> CGRect {
        guard !itemBounds.isEmpty else { return .zero }

        let screenFrame = screen.frame
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
            // AX status-item frames already include the button's internal
            // leading padding. Adding the legacy CGS 7 pt outset on macOS 27
            // leaves a conspicuous empty shelf before the first glyph (e.g.
            // AirPods). A small inner margin keeps the leftmost icon off the
            // rounded cap without reintroducing the full-width shelf.
            if #available(macOS 27, *) {
                return Constants.MenuBarTuning.trailingPillLeadingInnerMargin
            }
            return 7
        }()
        let trailingOutset: CGFloat = {
            if shouldInset {
                return 4
            }
            // macOS 27: the legacy 7 pt outset is narrower than the rounded cap
            // radius, so the right cap clips the rightmost item (the Clock).
            // Mirror the inner margin so the cap clears it.
            if #available(macOS 27, *) {
                return Constants.MenuBarTuning.trailingPillTrailingOuterMargin
            }
            return 7
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
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }

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
            // Widens only the trailing pill's own span, not the leading pill's
            // `trailingContentMinX` clamp computed above — see doc comment.
            // Only append when the chevron sits at or right of the existing
            // candidates: a reflow can temporarily place it far left, which
            // would pull contentMinX into empty space before the first icon.
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

        return splitShapePath(
            leadingPathBounds: resolvedBounds.leading,
            trailingPathBounds: resolvedBounds.trailing,
            info: info,
            in: rect,
            screen: screen
        )
    }

    /// Builds the split shape from resolved leading/trailing rectangles.
    private func splitShapePath(
        leadingPathBounds: CGRect,
        trailingPathBounds: CGRect,
        info: MenuBarSplitShapeInfo,
        in rect: CGRect,
        screen: NSScreen
    ) -> NSBezierPath {
        if leadingPathBounds == .zero || trailingPathBounds == .zero
            || leadingPathBounds.intersects(trailingPathBounds)
        {
            if leadingPathBounds != .zero, trailingPathBounds == .zero {
                return shapePath(
                    in: leadingPathBounds,
                    leadingEndCap: info.leading.leadingEndCap,
                    trailingEndCap: info.leading.trailingEndCap,
                    screen: screen
                )
            }
            // Trailing items known but app-menu frame not yet loaded: draw
            // only the trailing pill rather than a full-width fallback that
            // would cover the empty center of the bar.
            if leadingPathBounds == .zero, trailingPathBounds != .zero {
                return shapePath(
                    in: trailingPathBounds,
                    leadingEndCap: info.trailing.leadingEndCap,
                    trailingEndCap: info.trailing.trailingEndCap,
                    screen: screen
                )
            }
            // Both zero — geometry not yet loaded; draw nothing.
            if leadingPathBounds == .zero, trailingPathBounds == .zero {
                return NSBezierPath()
            }
            // Pills intersect (transient reflow): fall back to full-width.
            var fallbackRect = rect
            fallbackRect.origin.x += fullConfiguration.leftMargin
            fallbackRect.size.width -= (fullConfiguration.leftMargin + fullConfiguration.rightMargin)
            return shapePath(
                in: fallbackRect,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen
            )
        }

        let leadingPath = shapePath(
            in: leadingPathBounds,
            leadingEndCap: info.leading.leadingEndCap,
            trailingEndCap: info.leading.trailingEndCap,
            screen: screen
        )
        let trailingPath = shapePath(
            in: trailingPathBounds,
            leadingEndCap: info.trailing.leadingEndCap,
            trailingEndCap: info.trailing.trailingEndCap,
            screen: screen
        )
        let path = NSBezierPath()
        path.append(leadingPath)
        path.append(trailingPath)
        return path
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
        case .noTint, .glass:
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
        }
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
                    glassView.style = configuration.backgroundGlassStyle.nsGlassStyle
                }
                return
            }
            guard let realContent = panel.contentView else { return }
            isBackgroundGlassActive = true

            let container = NSView()
            container.wantsLayer = true

            let glassView = NSGlassEffectView()
            glassView.style = configuration.backgroundGlassStyle.nsGlassStyle
            glassView.cornerRadius = 0
            glassView.translatesAutoresizingMaskIntoConstraints = false

            realContent.removeFromSuperview()
            realContent.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(glassView, positioned: .below, relativeTo: nil)
            container.addSubview(realContent, positioned: .above, relativeTo: nil)
            panel.contentView = container

            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: container.topAnchor),
                glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glassView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),

                realContent.topAnchor.constraint(equalTo: container.topAnchor),
                realContent.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                realContent.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                realContent.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
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

    /// Adds or removes the tint glass effect subview, masked to the shape path.
    private func updateTintGlass() {
        if configuration.tintKind == .glass, let shapeCGPath {
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
            tintGlassView.style = configuration.tintGlassStyle.nsGlassStyle

            if configuration.hasBorder {
                tintGlassBorderLayer.path = shapeCGPath
                tintGlassBorderLayer.strokeColor = configuration.borderColor
                tintGlassBorderLayer.lineWidth = configuration.borderWidth * 2
                tintGlassBorderLayer.isHidden = false
            } else {
                tintGlassBorderLayer.isHidden = true
            }

            tintGlassView.isHidden = false
        } else if tintGlassView.superview != nil {
            tintGlassView.isHidden = true
            tintGlassBorderLayer.isHidden = true
        }
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
                pathForFullShape(
                    in: drawableBounds,
                    info: fullConfiguration.fullShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen
                )
            case .split:
                pathForSplitShape(
                    in: drawableBounds,
                    info: fullConfiguration.splitShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen
                )
            case .notch:
                pathForNotchShape(
                    in: drawableBounds,
                    info: fullConfiguration.notchShapeInfo,
                    isInset: fullConfiguration.isInset,
                    screen: overlayPanel.owningScreen
                )
            }

        shapeCGPath = shapePath.cgPath
        updateTintGlass()

        var hasBorder = false

        // Background always draws first (full area, behind shapes)
        drawBackground(in: drawableBounds)
        drawBackgroundShadow(in: drawableBounds)
        drawBackgroundBorder(in: drawableBounds)

        switch fullConfiguration.shapeKind {
        case .noShape:
            // No shape tint/shadow/border — background only
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
                borderPath.setClip()

                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}
