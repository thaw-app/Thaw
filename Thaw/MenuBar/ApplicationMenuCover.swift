//
//  ApplicationMenuCover.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel
import Observation
import ThawAXCore
import ThawCapture

/// Covers Finder's menu titles while the desktop is focused, with a strip
/// matching the bar. Unlike hideApplicationMenus(manual:), it neither steals
/// focus nor puts Thaw in the Dock.
///
/// The panel sits at .mainMenu + 1, eats clicks, and has sharingType = .none so
/// Thaw's capture loop never re-ingests it. Its fill is MenuBarBackdrop's
/// composite of what is behind the transparent bar, since a solid average
/// reads as a patch; the average is only the fallback until a capture lands.
@MainActor
@Observable
final class ApplicationMenuCover {
    private nonisolated let diagLog = DiagLog(category: "ApplicationMenuCover")

    /// Moving from a Finder window to the desktop fires no activation
    /// notification, so this polls, but only while Finder is frontmost.
    static let pollInterval: TimeInterval = 0.4

    private weak var appState: AppState?

    private var advancedSettings: AdvancedSettings?
    private var cancellables = Set<AnyCancellable>()

    /// Reused while a new capture is pending, so the fallback fill never
    /// flashes as a black square.
    private var lastBackdrop: CGImage?

    /// Installed only while Finder is frontmost.
    private var pollCancellable: AnyCancellable?

    private var panel: NSPanel?
    private var lastState: DesktopFocusState = .notFinder

    /// A capture for a rect the cover has since left is discarded, not stretched.
    private var capturedRect: CGRect?
    private var captureTask: Task<Void, Never>?

    var isEnabled: Bool {
        advancedSettings?.enableDesktopMenuHiding ?? false
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        advancedSettings = appState.settings.advanced
        cancellables = [observeSettingFlips(), observeAverageColors(), observeActivation()]
        update()
    }

    /// Observes the property rather than defaults, so the pane, a thaw:// flip
    /// and a profile apply are all caught.
    private func observeSettingFlips() -> AnyCancellable {
        guard let advanced = advancedSettings else { return AnyCancellable {} }
        return advanced.observe(\.enableDesktopMenuHiding) { [weak self] _ in
            self?.update()
        }
    }

    /// Re-captures when the average colour moves: wallpaper, display and
    /// appearance changes all also change what is behind the bar.
    private func observeAverageColors() -> AnyCancellable {
        let task = Task { @MainActor [weak self] in
            guard let menuBarManager = self?.appState?.menuBarManager else {
                return
            }
            let changes = Observations { menuBarManager.averageColors }
            for await _ in changes {
                self?.capturedRect = nil
                self?.update()
            }
        }
        return AnyCancellable { task.cancel() }
    }

    private func observeActivation() -> AnyCancellable {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            continuation.yield()
        }

        let task = Task { @MainActor [weak self] in
            defer { center.removeObserver(observer) }
            for await _ in stream {
                self?.update()
            }
        }
        return AnyCancellable {
            continuation.finish()
            task.cancel()
        }
    }

    // MARK: Reconciliation

    private func update() {
        guard isEnabled else {
            updatePolling(frontmostIsFinder: false)
            teardown()
            return
        }

        let state = currentFocusState()
        updatePolling(frontmostIsFinder: state != .notFinder)

        if state != lastState {
            diagLog.debug("focus state \(String(describing: lastState)) -> \(String(describing: state))")
            lastState = state
        }

        guard ApplicationMenuCoverPolicy.shouldCover(state) else {
            teardown()
            return
        }
        guard let cgRect = coverRect() else {
            // The menus are mid-rebuild; leaving the previous cover in place
            // would strand it over titles that have moved.
            teardown()
            return
        }
        present(cgRect)
    }

    private func updatePolling(frontmostIsFinder: Bool) {
        guard isEnabled, frontmostIsFinder else {
            pollCancellable = nil
            return
        }
        guard pollCancellable == nil else {
            return
        }
        pollCancellable = Timer
            .publish(every: Self.pollInterval, tolerance: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.update()
            }
    }

    private func currentFocusState() -> DesktopFocusState {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.bundleIdentifier == ApplicationMenuCoverPolicy.finderBundleIdentifier,
              let frontmost,
              let app = AXHelpers.application(for: frontmost)
        else {
            return .notFinder
        }
        let focused = app.value(kAXFocusedWindowAttribute) as? AXElement
        let subrole = focused?.value(kAXSubroleAttribute) as? String
        return DesktopFocusState.classify(
            frontmostBundleIdentifier: frontmost.bundleIdentifier,
            hasFocusedWindow: focused != nil,
            focusedWindowSubrole: subrole
        )
    }

    /// In CG-global coordinates, the space the capture uses; the panel flips
    /// it to Cocoa.
    private func coverRect() -> CGRect? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              let app = AXHelpers.application(for: frontmost),
              let menuBar = AXHelpers.menuBar(for: app)
        else {
            return nil
        }
        let titles = AXHelpers.children(for: menuBar).map { child in
            MenuBarTitleFrame(
                role: AXHelpers.roleString(for: child),
                frame: AXHelpers.frame(for: child) ?? .null
            )
        }
        return ApplicationMenuCoverPolicy.coverRect(forOrderedTitles: titles)
    }

    // MARK: The panel

    private func present(_ cgRect: CGRect) {
        guard let rect = NSScreen.cocoaRect(fromCG: cgRect) else {
            return
        }
        let isNew = panel == nil
        let panel = panel ?? makePanel()
        self.panel = panel

        if panel.frame != rect {
            panel.setFrame(rect, display: true)
        }
        if !panel.isVisible {
            panel.orderFront(nil)
            panel.registerAsMenuBarOverlay()
        }
        if isNew {
            diagLog.notice("application menus covered at \(NSStringFromRect(rect))")
        }
        refreshBackdrop(for: cgRect)
    }

    // MARK: The backdrop

    /// One capture at a time, keyed on the rect, since the poll calls update()
    /// every 0.4 s.
    private func refreshBackdrop(for cgRect: CGRect) {
        guard capturedRect != cgRect else {
            return
        }
        capturedRect = cgRect
        captureTask?.cancel()

        // The capture takes long enough that the fallback shows as a slab, so
        // prefer the previous backdrop.
        if let lastBackdrop {
            panel?.contentView?.layer?.contents = lastBackdrop
        } else {
            panel?.backgroundColor = fillColor()
            panel?.contentView?.layer?.contents = nil
        }

        captureTask = Task { @MainActor [weak self] in
            // A window-server composite, so the recording indicator never lights.
            let image = await self?.appState?.menuBarManager.backdrop.capture(cgRect)
            guard !Task.isCancelled,
                  let self,
                  let image,
                  capturedRect == cgRect,
                  let panel,
                  let layer = panel.contentView?.layer
            else {
                return
            }
            self.lastBackdrop = image
            layer.contentsGravity = .resize
            layer.contentsScale = panel.backingScaleFactor
            layer.contents = image
        }
    }

    /// The stand-in fill. On a blurred, non-transparent bar the average is
    /// indistinguishable from the bar itself.
    private func fillColor() -> NSColor {
        guard let displayID = NSScreen.screenWithActiveMenuBar?.displayID ?? NSScreen.main?.displayID,
              let info = appState?.menuBarManager.averageColors[displayID],
              let color = NSColor(cgColor: info.color)
        else {
            // Without a sample, the window background still adapts to the
            // appearance; a black slab over a light bar reads as a fault.
            return .windowBackgroundColor
        }
        return color
    }

    private func makePanel() -> NSPanel {
        // Absorbs clicks so a covered title cannot be opened blind.
        let panel = NSPanel.menuBarOverlay(opaque: true, absorbsClicks: true)
        let content = NSView()
        content.wantsLayer = true
        panel.contentView = content
        return panel
    }

    private func teardown() {
        captureTask?.cancel()
        captureTask = nil
        capturedRect = nil
        guard let panel else {
            return
        }
        panel.unregisterAsMenuBarOverlay()
        panel.orderOut(nil)
        self.panel = nil
        diagLog.notice("application menu cover removed")
    }
}
