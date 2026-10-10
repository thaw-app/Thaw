//
//  ClockBridgeCover.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import os.lock

/// Hides the hidden items that flash into the bar while Thaw has to lift its
/// concealment for a Clock click or the Notification Center shortcut.
///
/// Only those bridges raise it. Icon capture passes do not: their reveals
/// run for seconds, and a cover anchored on a misplaced visible item hid
/// the live bar for the whole pass.
///
/// The bridge has to drop the whole visibility restriction, because the held
/// assertion swallows those gestures, and for the second or so it is down
/// every concealed item draws left of the visible ones. The visible items do
/// not move: the bar is anchored right, so the flash is confined to a band
/// that is otherwise empty bar. This covers that band with what is behind the
/// bar, so for the length of the bridge the bar looks as it did.
///
/// The band is painted with MenuBarBackdrop's strip, captured ahead of
/// time and without ScreenCaptureKit, so a press never waits on a capture and
/// never lights the recording indicator.
@MainActor
final class ClockBridgeCover {
    private weak var appState: AppState?
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var hideTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var watchdogDeadline: ContinuousClock.Instant?
    private var holders = 0
    private let diagLog = DiagLog(category: "ClockBridgeCover")

    /// Held after the assertion is back: the host keeps drawing the revealed
    /// items for roughly a second after the restriction returns.
    static let settleAfterRestore = Duration.milliseconds(1000)
    /// A cover never outlives this, whatever the bridge does. A stuck cover is
    /// a frozen strip of bar, which is worse than the flash it hides.
    static let maximumLifetime = Duration.seconds(4)
    /// Room left for the pill's rounded end left of the first visible item.
    static nonisolated let pillInset: CGFloat = 10
    /// Gap macOS leaves between adjacent status items.
    static let itemSpacing: CGFloat = 8
    /// Least width an item counts for when its reported width is unusable.
    static let minimumItemWidth: CGFloat = 24
    /// Slack on the summed width, for estimates that come in short.
    static let widthMargin: CGFloat = 1.25
    /// Length of the fade at the band's left end.
    static let fadeWidth: CGFloat = 32

    func performSetup(with appState: AppState) {
        self.appState = appState
    }

    // MARK: Bridge

    /// Covers the band the concealed items will appear in. Call right before
    /// the restriction is released.
    ///
    /// Covers are counted: overlapping bridges share one cover, and it comes
    /// down only when the last holder lets go.
    func show() {
        hideTask?.cancel()
        holders += 1
        armWatchdog(Self.maximumLifetime)
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
        guard watchdogDeadline.map({ deadline > $0 }) ?? true else { return }
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
        // The Thaw icon is the leftmost visible item on most bars and does not
        // always report itself on screen, so it is taken on its bounds alone.
        let visible = items.filter { item in
            item.bounds.width > 0
                && (item.tag.matchesVisibleControlItem || (item.isOnScreen && controller.section(for: item) == .visible))
        }
        // Parked items can report a zero or shrunken width, and a leak at the
        // far end is the one failure a user sees, so each counts at least
        // minimumItemWidth and the total carries widthMargin.
        let concealedWidth = items
            .filter { !$0.tag.matchesVisibleControlItem && controller.section(for: $0) != .visible }
            .reduce(CGFloat.zero) { $0 + max($1.bounds.width, minimumItemWidth) + itemSpacing } * widthMargin
        let screens = NSScreen.screens.map { screen in
            ScreenBar(
                displayID: screen.displayID,
                frame: screen.cgFrame,
                height: screen.getMenuBarHeight() ?? screen.getMenuBarHeightEstimate()
            )
        }
        return Layout(bands: bands(
            visibleFrames: visible.map(\.bounds),
            liveAnchorX: liveAnchorX,
            screens: screens,
            concealedWidth: concealedWidth
        ))
    }

    /// A display's CG-global frame and menu bar height.
    nonisolated struct ScreenBar: Sendable {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let height: CGFloat
    }

    /// The cover band per display, from the frames of the visible items.
    ///
    /// Only seated frames anchor: an item parked at the x == -1 sentinel still
    /// reports itself on screen and would leave every display uncovered. A
    /// display without seated items mirrors the right-edge distance of the
    /// home display, the one liveAnchorX was read on.
    static nonisolated func bands(
        visibleFrames: [CGRect],
        liveAnchorX: CGFloat?,
        screens: [ScreenBar],
        concealedWidth: CGFloat
    ) -> [CGDirectDisplayID: CGRect] {
        guard concealedWidth > 0 else { return [:] }
        let screenFrames = screens.map(\.frame)
        var leadingEdges: [CGDirectDisplayID: CGFloat] = [:]
        var home: (screen: ScreenBar, x: CGFloat)?
        for frame in visibleFrames {
            guard let seat = MenuBarItemGeometry.barScreen(holding: frame, among: screenFrames),
                  let screen = screens.first(where: { $0.frame == seat })
            else {
                continue
            }
            leadingEdges[screen.displayID] = min(leadingEdges[screen.displayID] ?? frame.minX, frame.minX)
            if home.map({ frame.minX < $0.x }) ?? true {
                home = (screen, frame.minX)
            }
        }
        guard let home else { return [:] }
        if let liveAnchorX, liveAnchorX > home.screen.frame.minX, liveAnchorX < home.screen.frame.maxX {
            leadingEdges[home.screen.displayID] = liveAnchorX
        }
        let homeEdge = leadingEdges[home.screen.displayID] ?? home.x
        let offsetFromRight = home.screen.frame.maxX - (homeEdge - pillInset)
        var bands: [CGDirectDisplayID: CGRect] = [:]
        for screen in screens {
            let frame = screen.frame
            let right = leadingEdges[screen.displayID].map { $0 - pillInset } ?? frame.maxX - offsetFromRight
            let left = max(frame.minX, right - concealedWidth - pillInset)
            guard right > left else { continue }
            bands[screen.displayID] = CGRect(x: left, y: frame.minY, width: right - left, height: screen.height)
        }
        return bands
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
        panel.contentView?.layer?.mask = Self.fadeMask(width: band.width, height: band.height)
        panel.setFrame(cocoa, display: false)
        if !isShowing {
            // The chevron probe hit-tests the bar, and would read the cover.
            ClockRevealMaskActivity.noteShown()
        }
        panel.orderFrontRegardless()
        panel.registerAsMenuBarOverlay()
    }

    /// Lays Thaw's own look over the wallpaper, so the covered band matches
    /// the styled bar beside it instead of showing bare wallpaper. See
    /// ClockBridgeCoverStyle for why this is painted, not captured.
    private func applyStyle(to layer: CALayer, on displayID: CGDirectDisplayID) {
        layer.sublayers?.removeAll()
        layer.filters = nil
        guard let appState else { return }
        let configuration = appState.appearanceManager.effectiveConfiguration
        let style = ClockBridgeCoverStyle.style(
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
            ClockRevealMaskActivity.noteHidden()
        }
        for panel in panels.values where panel.isVisible {
            panel.unregisterAsMenuBarOverlay()
            panel.orderOut(nil)
        }
    }

    /// Fades the band in over its left end. The backdrop is a hair off the
    /// live bar, and a hard edge makes that difference a visible seam; a fade
    /// spreads it over fadeWidth, where it reads as the bar.
    private static func fadeMask(width: CGFloat, height: CGFloat) -> CALayer {
        let mask = CAGradientLayer()
        mask.frame = CGRect(x: 0, y: 0, width: width, height: height)
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
        mask.locations = [0, NSNumber(value: Double(min(fadeWidth / max(width, 1), 0.5))), 1]
        return mask
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

/// Whether a ClockBridgeCover is up, so the nonisolated chevron probe can
/// tell a covered hit-test from a real bar reading.
nonisolated enum ClockRevealMaskActivity {
    private static let activeCount = OSAllocatedUnfairLock(initialState: 0)

    static var isAnyMaskShowing: Bool {
        activeCount.withLock { $0 > 0 }
    }

    static func noteShown() {
        activeCount.withLock { $0 += 1 }
    }

    static func noteHidden() {
        activeCount.withLock { $0 = max(0, $0 - 1) }
    }
}
