//
//  RevealCover.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// Covers the band where concealed items flash during an icon capture's reveal
/// with MenuBarBackdrop's strip, so the bar looks unchanged and no recording
/// indicator lights. The band ends at the leading edge read at show(), so it
/// never sits over visible items. Clock and Notification Center get no cover:
/// the bar restyles itself as they open.
@MainActor
final class RevealCover {
    private weak var appState: AppState?
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var hideTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var watchdogDeadline: ContinuousClock.Instant?
    private var holders = 0
    private let diagLog = DiagLog(category: "RevealCover")

    /// Held after the assertion is back: the host keeps drawing the revealed
    /// items for roughly a second after the restriction returns.
    static let settleAfterRestore = Duration.milliseconds(1000)

    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    // MARK: Bridge

    /// Covers the band the concealed items will appear in. Call right before
    /// the restriction is released.
    ///
    /// Covers are counted: overlapping bridges share one cover, and it comes
    /// down only when the last holder lets go. The cover never outlives
    /// lifetime, since a stuck cover freezes a strip of bar.
    func show(lifetime: Duration) {
        hideTask?.cancel()
        holders += 1
        armWatchdog(lifetime)
        guard holders == 1 || !isShowing, let appState else { return }
        // One position read on an element found ahead of time: a single
        // short IPC, cheap enough for the event tap, and it keeps a stale
        // cache from placing the band over the first visible icon.
        let liveX = appState.menuBarManager.leadingEdgeWatcher.readNow()
        let layout = Self.coverLayout(appState: appState, liveAnchorX: liveX)
        var covered = 0
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            guard let band = layout.bands[displayID] else {
                // Hidden items will show on this display for the whole bridge.
                diagLog.warning("no cover on display \(displayID): no band (\(layout.bands.isEmpty ? "no seated visible item to anchor on" : "band empty on this display"))")
                continue
            }
            guard let backdrop = appState.menuBarManager.backdrop.strip(for: displayID) else {
                diagLog.warning("no cover on display \(displayID): no backdrop strip; refreshing it for next time")
                appState.menuBarManager.backdrop.refresh(force: true)
                continue
            }
            present(band, backdrop: backdrop, on: displayID)
            covered += 1
        }
        diagLog.debug("cover up on \(covered) of \(NSScreen.screens.count) display(s), \(liveX == nil ? "on cached bounds" : "on the live bar")")
    }

    /// Pushed out by each new holder, never pulled in.
    private func armWatchdog(_ lifetime: Duration) {
        let deadline = ContinuousClock.now.advanced(by: lifetime)
        guard RevealCoverGeometry.extendsWatchdog(to: deadline, from: watchdogDeadline) else { return }
        watchdogDeadline = deadline
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(until: deadline)
            guard !Task.isCancelled, let self else { return }
            diagLog.warning("cover outlived its holders; removing it")
            holders = 0
            orderOutAll()
        }
    }

    /// Removes the cover once the host has stopped drawing the revealed items.
    /// Call when the restriction is back, or at once when it never dropped.
    func hide(immediately: Bool = false) {
        guard holders > 0 else { return }
        holders -= 1
        guard holders == 0 else { return }
        hideTask?.cancel()
        guard !immediately else {
            orderOutAll()
            return
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleAfterRestore)
            guard !Task.isCancelled else { return }
            self?.orderOutAll()
            // Cheap and capture-indicator free, so take the chance to pick up
            // anything that moved behind the bar during the bridge.
            self?.appState?.menuBarManager.backdrop.refresh()
        }
    }

    // MARK: Geometry

    /// Per display, the band in CG-global coordinates that the concealed items
    /// will occupy: from the left of the first visible item leftwards, by the
    /// width they take. The visible run is right-anchored, so a bar mirrored on
    /// another display puts the band at the same distance from its right edge.
    private struct Layout {
        var bands: [CGDirectDisplayID: CGRect]
    }

    /// liveAnchorX, when known, replaces the cached left edge of the first
    /// visible item.
    private static func coverLayout(appState: AppState, liveAnchorX: CGFloat?) -> Layout {
        let controller = appState.menuBarManager.sectionController
        let items = appState.itemManager.managedItems
        let visible = items.filter { item in
            RevealCoverGeometry.anchorsBand(
                width: item.bounds.width,
                isVisibleControlItem: item.tag.matchesVisibleControlItem,
                isOnScreen: item.isOnScreen,
                isInVisibleSection: controller.section(for: item) == .visible
            )
        }
        let concealedWidth = RevealCoverGeometry.concealedWidth(itemWidths: items
            .filter { item in
                RevealCoverGeometry.isConcealed(
                    isVisibleControlItem: item.tag.matchesVisibleControlItem,
                    isInVisibleSection: controller.section(for: item) == .visible
                )
            }
            .map(\.bounds.width))
        let screens = NSScreen.screens.map { screen in
            RevealCoverGeometry.ScreenBar(
                displayID: screen.displayID,
                frame: screen.cgFrame,
                height: screen.getMenuBarHeight() ?? screen.getMenuBarHeightEstimate()
            )
        }
        return Layout(bands: RevealCoverGeometry.bands(
            visibleFrames: visible.map(\.bounds),
            liveAnchorX: liveAnchorX,
            screens: screens,
            concealedWidth: concealedWidth
        ))
    }

    // MARK: Panels

    private func present(_ band: CGRect, backdrop: MenuBarBackdrop.Strip, on displayID: CGDirectDisplayID) {
        guard let cocoa = NSScreen.cocoaRect(fromCG: band) else { return }
        let panel = panels[displayID] ?? makePanel()
        panels[displayID] = panel
        if let layer = panel.contentView?.layer {
            // Show only the slice of the strip under the band.
            layer.contents = backdrop.image
            layer.contentsGravity = .resize
            layer.contentsRect = backdrop.contentsRect(for: band)
            applyStyle(to: layer, on: displayID)
        }
        panel.contentView?.layer?.mask = RevealCoverGeometry.fadeMask(width: band.width, height: band.height)
        panel.setFrame(cocoa, display: false)
        if !isShowing {
            // The chevron probe hit-tests the bar, and would read the cover.
            RevealCoverActivity.noteShown()
        }
        panel.orderFrontRegardless()
        panel.registerAsMenuBarOverlay()
    }

    /// Lays Thaw's own look over the wallpaper, so the covered band matches
    /// the styled bar beside it instead of showing bare wallpaper. See
    /// RevealCoverStyle for why this is painted, not captured.
    private func applyStyle(to layer: CALayer, on displayID: CGDirectDisplayID) {
        layer.sublayers?.removeAll()
        layer.filters = nil
        guard let appState else { return }
        let configuration = appState.appearanceManager.effectiveConfiguration
        let style = RevealCoverStyle.style(
            for: configuration.current,
            shapeKind: configuration.shapeKind,
            adaptiveColor: appState.menuBarManager.averageColors[displayID]?.color
        )
        if style.blursWallpaper, let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(8, forKey: kCIInputRadiusKey)
            layer.filters = [blur]
            layer.masksToBounds = true
        }
        for wash in style.washes {
            let fill = CALayer()
            fill.frame = layer.bounds
            fill.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            fill.backgroundColor = wash.color
            fill.opacity = Float(wash.opacity)
            layer.addSublayer(fill)
        }
    }

    private var isShowing: Bool {
        panels.values.contains(where: \.isVisible)
    }

    private func orderOutAll() {
        watchdog?.cancel()
        watchdog = nil
        watchdogDeadline = nil
        if isShowing {
            RevealCoverActivity.noteHidden()
        }
        for panel in panels.values where panel.isVisible {
            panel.unregisterAsMenuBarOverlay()
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        // Not opaque: the left end fades into the live bar. Clicks go through
        // to the bar: this only has to be seen, and it is up for a second.
        let panel = NSPanel.menuBarOverlay(opaque: false, absorbsClicks: false)
        #if DEBUG
            // A debug build can let capture see it, so a screen recording can
            // check the cover.
            if UserDefaults.standard.bool(forKey: "ClockBridgeCoverCapturable") {
                panel.sharingType = .readOnly
            }
        #endif
        let content = NSView()
        content.wantsLayer = true
        // The glass looks blur the wallpaper slice with a Core Image filter.
        content.layerUsesCoreImageFilters = true
        panel.contentView = content
        return panel
    }
}
