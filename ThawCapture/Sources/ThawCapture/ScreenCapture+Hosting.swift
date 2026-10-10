//
//  ScreenCapture+Hosting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import os.lock
import ScreenCaptureKit

public extension ScreenCapture {
    /// Wait for a recent display composite before reading the warm stream.
    /// MenuBarAgent may redraw shortly after conceal/reveal/move. This window
    /// spans a frame at the stream's 10 fps limit; it reduces first-frame races
    /// but cannot prove that an application has finished redrawing its glyphs.
    static let stripSettleWindow = Duration.milliseconds(120)

    /// Longest a single SCScreenshotManager capture may run before it counts
    /// as wedged. The live loop awaits captures inline, so one hang stalls it.
    static let screenshotTimeout: Duration = .seconds(5)

    /// How long a display's failed hosting-window lookup is trusted before the
    /// window enumeration is repeated. Longer than a live refresh tick, short
    /// enough that a reconnected display is picked up within a few seconds.
    static let hostingWindowMissTTL: Duration = .seconds(3)

    /// When each display's hosting-window lookup last found nothing, so ticks
    /// skip a full SCShareableContent enumeration for the same answer.
    private static let hostingWindowMisses = OSAllocatedUnfairLock<[CGDirectDisplayID: ContinuousClock.Instant]>(
        initialState: [:]
    )

    /// Registered once, on the first recorded miss. A display change makes
    /// every remembered miss stale, so it empties the table outright.
    private static let hostingWindowMissReconfigurationObserver: Void = {
        _ = CGDisplayRegisterReconfigurationCallback({ _, _, _ in
            ScreenCapture.clearHostingWindowMisses()
        }, nil)
    }()

    /// Whether a miss recorded for this display is still within its TTL.
    static func isHostingWindowMissFresh(
        on displayID: CGDirectDisplayID,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        hostingWindowMisses.withLock { misses in
            guard let missedAt = misses[displayID] else { return false }
            return now - missedAt < hostingWindowMissTTL
        }
    }

    /// Records a miss and reports whether it is the first since the display
    /// last resolved, so the caller can warn once and demote the repeats.
    static func recordHostingWindowMiss(
        on displayID: CGDirectDisplayID,
        now: ContinuousClock.Instant = .now
    ) -> Bool {
        _ = hostingWindowMissReconfigurationObserver
        return hostingWindowMisses.withLock { misses in
            misses.updateValue(now, forKey: displayID) == nil
        }
    }

    /// Forgets a display's miss once its hosting window resolves again.
    static func clearHostingWindowMiss(on displayID: CGDirectDisplayID) {
        hostingWindowMisses.withLock { _ = $0.removeValue(forKey: displayID) }
    }

    /// Whether the ScreenCaptureKit window filter may back the hosting window.
    /// The capture helper turns it off: SkyLight asserts inside that filter.
    static nonisolated(unsafe) var desktopIndependentWindowCaptureEnabled = true

    /// Points-to-pixels for a display, or 1 when it cannot be read.
    static func displayPixelScale(_ displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.width > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }

    /// Forgets every remembered miss; used on display reconfiguration.
    static func clearHostingWindowMisses() {
        hostingWindowMisses.withLock { $0.removeAll() }
    }

    // MARK: - ScreenCaptureKit Implementation

    /// A captured frame together with the geometry needed to crop items out of
    /// it. Used for every capture Thaw crops thumbnails from: MenuBarAgent's
    /// hosting window and the display strip.
    ///
    /// Unchecked Sendable: the only reference member is an immutable CGImage.
    struct MenuBarHostingCapture: @unchecked Sendable {
        /// The captured image of the whole menu bar (every status item
        /// composited on a transparent background, at scale).
        public let image: CGImage
        /// The hosting window's frame in global screen coordinates
        /// (Y-down). Subtract this origin from an item's frame to map it
        /// into the image, then multiply by scale.
        public let windowFrame: CGRect
        /// The pixel scale the image was captured at.
        public let scale: CGFloat

        /// Builds a capture from an image the caller took itself, which must
        /// follow the same contract: items on transparency from windowFrame.
        public init(image: CGImage, windowFrame: CGRect, scale: CGFloat) {
            self.image = image
            self.windowFrame = windowFrame
            self.scale = scale
        }
    }

    /// Whether an SCWindow frame matches the full-width menu-bar strip geometry
    /// (point-space or pixel-backed, as reported by some macOS 27 builds).
    static func windowMatchesMenuBarStripGeometry(
        _ frame: CGRect,
        displayFrame: CGRect
    ) -> Bool {
        let pointSpace =
            frame.height <= 60
                && frame.width > displayFrame.width * 0.8
                && abs(frame.minX - displayFrame.minX) < 2
                && abs(frame.minY - displayFrame.minY) < 2
        let pixelSpace =
            frame.height > 60
                && frame.height <= 120
                && frame.width > displayFrame.width * 1.5
                && abs(frame.minX - displayFrame.minX) < 2
                && abs(frame.minY - displayFrame.minY) < 2
        return pointSpace || pixelSpace
    }

    static func menuBarHostingWindowCandidates(
        in content: SCShareableContent,
        displayFrame: CGRect
    ) -> [SCWindow] {
        content.windows.filter { w in
            guard w.owningApplication?.bundleIdentifier == SharedConstants.menuBarHostingBundleID else {
                return false
            }
            return windowMatchesMenuBarStripGeometry(w.frame, displayFrame: displayFrame)
        }
    }

    /// Whether windowFrame looks like backing pixels rather than points.
    ///
    /// Cropping AX point-space bounds with a pixel-backed frame (or multiplying
    /// that frame by pointPixelScale again) vertically half-slices every glyph.
    static func windowFrameAppearsPixelBacked(
        _ windowFrame: CGRect,
        displayFrame: CGRect
    ) -> Bool {
        guard displayFrame.width > 0 else { return false }
        return windowFrame.height > 40
            || windowFrame.width > displayFrame.width * 1.5
    }

    /// Pixel size to request from ScreenCaptureKit for the hosting window.
    ///
    /// A pixel-backed windowFrame is not scaled again: a 2× buffer makes SCK's
    /// rescale shred Liquid Glass glyphs into columns.
    static func hostingCapturePixelSize(
        windowFrame: CGRect,
        displayFrame: CGRect,
        reportedScale: CGFloat
    ) -> (width: Int, height: Int) {
        if windowFrameAppearsPixelBacked(windowFrame, displayFrame: displayFrame) {
            return (
                max(1, Int(windowFrame.width.rounded())),
                max(1, Int(windowFrame.height.rounded()))
            )
        }
        let scale = max(reportedScale, 0.5)
        return (
            max(1, Int((windowFrame.width * scale).rounded())),
            max(1, Int((windowFrame.height * scale).rounded()))
        )
    }

    /// Normalizes a hosting-window bitmap into point-space windowFrame + scale
    /// suitable for cropping AX bounds (also point-space).
    ///
    /// Derives scale from the bitmap whenever possible so a mismatched
    /// pointPixelScale cannot half-slice icons.
    static func normalizedHostingCapture(
        image: CGImage,
        windowFrame: CGRect,
        displayFrame: CGRect,
        reportedScale: CGFloat
    ) -> MenuBarHostingCapture? {
        guard image.width > 0, image.height > 0,
              displayFrame.width > 0, displayFrame.height > 0
        else {
            return nil
        }

        if windowFrameAppearsPixelBacked(windowFrame, displayFrame: displayFrame) {
            let scale = CGFloat(image.width) / displayFrame.width
            guard scale > 0.5, scale < 6,
                  abs(CGFloat(image.width) - displayFrame.width * scale) <= 3
            else {
                return nil
            }
            let pointFrame = CGRect(
                x: displayFrame.minX,
                y: displayFrame.minY,
                width: displayFrame.width,
                height: CGFloat(image.height) / scale
            )
            return MenuBarHostingCapture(image: image, windowFrame: pointFrame, scale: scale)
        }

        guard windowFrame.width > 0, windowFrame.height > 0 else {
            return nil
        }

        // The bitmap/frame ratio beats reportedScale, which can drift from the
        // buffer and half-cut glyphs.
        let scale = CGFloat(image.width) / windowFrame.width
        guard scale > 0.5, scale < 6 else {
            return nil
        }
        let expectedHeight = windowFrame.height * scale
        if abs(CGFloat(image.height) - expectedHeight) > 3 {
            // Axes disagree, fall back to the display's point width.
            let displayScale = CGFloat(image.width) / displayFrame.width
            guard displayScale > 0.5, displayScale < 6 else {
                return nil
            }
            return MenuBarHostingCapture(
                image: image,
                windowFrame: CGRect(
                    x: displayFrame.minX,
                    y: displayFrame.minY,
                    width: displayFrame.width,
                    height: CGFloat(image.height) / displayScale
                ),
                scale: displayScale
            )
        }

        _ = reportedScale
        return MenuBarHostingCapture(image: image, windowFrame: windowFrame, scale: scale)
    }

    static func logMenuBarHostingWindowCandidates(
        displayID: CGDirectDisplayID,
        reason: String
    ) async {
        guard isProbeLoggingEnabled() else {
            return
        }

        let content: SCShareableContent
        do {
            content = try await getShareableContent()
        } catch {
            diagLog.error("hostingCandidates[\(reason)]: SCShareableContent failed: \(error)")
            return
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            diagLog.warning("hostingCandidates[\(reason)]: display \(displayID) not found")
            return
        }

        let candidates = menuBarHostingWindowCandidates(in: content, displayFrame: display.frame)
        let descriptions = candidates
            .sorted { $0.windowID < $1.windowID }
            .map { window in
                "wid=\(window.windowID) frame=\(NSStringFromRect(window.frame))"
            }
        diagLog.info(
            "hostingCandidates[\(reason)]: displayID=\(displayID) " +
                "count=\(candidates.count) \(descriptions.joined(separator: " | "))"
        )
    }

    /// The old fixed strip height, kept as the floor.
    static let minimumMenuBarDisplayStripHeight: CGFloat = 40

    /// How tall a display's strip has to be to hold its whole menu bar.
    ///
    /// Apple's modules report the full bar height, 49 pt on some notched
    /// panels, and a crop cut short is discarded.
    ///
    /// - Parameter menuBarHeight: The live menu bar height, nil if unknown.
    static func menuBarDisplayStripHeight(menuBarHeight: CGFloat?) -> CGFloat {
        max(minimumMenuBarDisplayStripHeight, menuBarHeight ?? 0)
    }

    /// The live menu bar height of a display, read from its backdrop window,
    /// the same window the app sizes its own layout against.
    static func liveMenuBarHeight(for displayID: CGDirectDisplayID) -> CGFloat? {
        WindowInfo.menuBarWindow(for: displayID)?.bounds.height
    }

    /// Point-space menu-bar strip used when third-party glyphs must be read from
    /// the on-screen display composite rather than MenuBarAgent's hosting window.
    static func menuBarDisplayStripFrame(
        displayFrame: CGRect,
        height: CGFloat = minimumMenuBarDisplayStripHeight
    ) -> CGRect {
        CGRect(
            x: displayFrame.minX,
            y: displayFrame.minY,
            width: displayFrame.width,
            height: min(max(height, 1), displayFrame.height)
        )
    }

    /// Window-level threshold above which an on-screen window overlapping the
    /// menu-bar strip is treated as a foreign overlay to exclude from the strip
    /// capture.
    ///
    /// Nothing worth reading lives above the main menu level on macOS 27;
    /// anything there (notch simulators, drop shelves) bleeds into crops.
    static var menuBarStripOverlayLevelThreshold: Int {
        Int(CGWindowLevelForKey(.mainMenuWindow))
    }

    /// Whether a window overlapping the menu-bar strip is a foreign overlay that
    /// would pollute status-item crops and should be excluded from the strip
    /// capture.
    ///
    /// Pure so it can be unit-tested without a live SCWindow set.
    static func isMenuBarStripOverlay(
        frame: CGRect,
        windowLayer: Int,
        isOnScreen: Bool,
        stripFrame: CGRect
    ) -> Bool {
        guard isOnScreen else { return false }
        guard windowLayer > menuBarStripOverlayLevelThreshold else { return false }
        return frame.intersects(stripFrame)
    }

    /// Whether a window overlapping the strip belongs to Thaw itself and must
    /// be excluded from the strip capture regardless of its level.
    ///
    /// The overlay sits at the menu bar level, so the level cut cannot catch it,
    /// and self-sampled glass would feed back into the average color. Matched
    /// by pid in process and by bundle prefix in the capture service.
    ///
    /// Pure so it can be unit-tested without SCWindow.
    static func isOwnMenuBarSurface(
        ownerPID: pid_t?,
        ownerBundleIdentifier: String?,
        frame: CGRect,
        isOnScreen: Bool,
        stripFrame: CGRect,
        selfPID: pid_t
    ) -> Bool {
        guard isOnScreen, frame.intersects(stripFrame) else { return false }
        if ownerPID == selfPID {
            return true
        }
        guard let ownerBundleIdentifier else { return false }
        return ownerBundleIdentifier.hasPrefix("com.stonerl.Thaw")
    }

    /// The set of windows to exclude from a strip capture: foreign overlays
    /// floating above the bar (notch simulators, drop shelves) plus Thaw's own
    /// menu-bar surfaces at any level, so the composite reveals the real menu
    /// bar beneath both.
    static func menuBarStripOverlayWindows(
        in content: SCShareableContent,
        stripFrame: CGRect
    ) -> [SCWindow] {
        let selfPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return content.windows.filter { window in
            isMenuBarStripOverlay(
                frame: window.frame,
                windowLayer: window.windowLayer,
                isOnScreen: window.isOnScreen,
                stripFrame: stripFrame
            ) || isOwnMenuBarSurface(
                ownerPID: window.owningApplication.map { pid_t($0.processID) },
                ownerBundleIdentifier: window.owningApplication?.bundleIdentifier,
                frame: window.frame,
                isOnScreen: window.isOnScreen,
                stripFrame: stripFrame,
                selfPID: selfPID
            )
        }
    }

    /// Captures the on-screen menu-bar band of a display (menu-bar-level windows
    /// composited, foreign overlays above the bar excluded).
    ///
    /// Third-party Liquid Glass shreds in the hosting window under SCK. The
    /// strip matches the screen; callers knock out the bar fill after cropping.
    ///
    /// - Parameter displayID: The display whose menu bar band to capture.
    /// - Returns: The strip capture, or nil on failure.
    static func captureMenuBarDisplayStripAsync(
        displayID: CGDirectDisplayID,
        preferInProcess: Bool = false
    ) async -> MenuBarHostingCapture? {
        guard let visibilityGeneration = captureUITicket(), !Task.isCancelled else { return nil }
        // Fall through to in-process when the helper cannot answer.
        // preferInProcess is for the reveal mask, which must answer in
        // milliseconds; the helper's round trip shows as a slow Notification Center.
        if routesThroughCaptureService,
           !preferInProcess,
           let viaService = await MenuBarCaptureServiceClient.shared.captureMenuBarDisplayStrip(
               displayID: displayID,
               visibilityGeneration: visibilityGeneration
           )
        {
            return viaService
        }
        let content: SCShareableContent
        do {
            content = try await getShareableContent()
        } catch {
            diagLog.error("captureMenuBarDisplayStripAsync: SCShareableContent failed: \(error)")
            return nil
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            diagLog.warning("captureMenuBarDisplayStripAsync: display \(displayID) not found")
            return nil
        }

        let displayFrame = display.frame
        let stripFrame = menuBarDisplayStripFrame(
            displayFrame: displayFrame,
            height: menuBarDisplayStripHeight(menuBarHeight: liveMenuBarHeight(for: displayID))
        )
        // Overlays above the menu bar level would bleed into item crops.
        let overlayWindows = menuBarStripOverlayWindows(in: content, stripFrame: stripFrame)
        if !overlayWindows.isEmpty {
            diagLog.debug(
                "captureMenuBarDisplayStripAsync: excluding \(overlayWindows.count) menu-bar overlay window(s)"
            )
        }
        let filter = SCContentFilter(display: display, excludingWindows: overlayWindows)
        let reportedScale = CGFloat(filter.pointPixelScale)

        let scale = max(reportedScale, 0.5)

        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        configuration.capturesAudio = false
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureDynamicRange = .SDR
        configuration.width = max(1, Int((stripFrame.width * scale).rounded()))
        configuration.height = max(1, Int((stripFrame.height * scale).rounded()))
        configuration.sourceRect = CGRect(
            x: stripFrame.minX - displayFrame.minX,
            y: stripFrame.minY - displayFrame.minY,
            width: stripFrame.width,
            height: stripFrame.height
        )

        do {
            let image = try await DisplayStripCaptureSession.shared.capture(
                key: .init(
                    displayID: displayID,
                    displayFrame: displayFrame,
                    stripFrame: stripFrame,
                    scale: scale,
                    excludedWindowIDs: overlayWindows.map(\.windowID).sorted()
                ),
                visibilityGeneration: visibilityGeneration,
                filter: filter,
                configuration: configuration
            )
            guard isCaptureUITicketCurrent(visibilityGeneration) else { return nil }
            guard let normalized = normalizedHostingCapture(
                image: image,
                windowFrame: stripFrame,
                displayFrame: displayFrame,
                reportedScale: reportedScale
            ) else {
                diagLog.warning(
                    "captureMenuBarDisplayStripAsync: rejected unnormalizable capture " +
                        "\(image.width)×\(image.height)px strip=\(stripFrame) " +
                        "display=\(displayFrame) reportedScale=\(reportedScale)"
                )
                return nil
            }
            diagLog.debug(
                "captureMenuBarDisplayStripAsync: captured \(image.width)×\(image.height)px " +
                    "scale=\(normalized.scale) pointFrame=\(normalized.windowFrame) " +
                    "for displayID=\(displayID)"
            )
            return normalized
        } catch is TaskTimeoutError {
            diagLog.error(
                "captureMenuBarDisplayStripAsync: display strip stream timed out after \(Self.screenshotTimeout.components.seconds)s"
            )
            return nil
        } catch is CancellationError {
            // Debug, not error: cancellation is how a superseded capture retires.
            diagLog.debug("captureMenuBarDisplayStripAsync: capture cancelled; superseded")
            return nil
        } catch {
            diagLog.error("captureMenuBarDisplayStripAsync: display strip stream failed: \(error)")
            return nil
        }
    }

    /// Captures MenuBarAgent's menu bar hosting window for a display.
    ///
    /// On macOS 27 every status item is composited in one full-width window,
    /// which captures as glyphs on transparency.
    ///
    /// - Parameter displayID: The display whose menu bar to capture.
    /// - Returns: The capture, or nil if the hosting window can't be found
    ///   or captured.
    static func captureMenuBarHostingWindowAsync(
        displayID: CGDirectDisplayID
    ) async -> MenuBarHostingCapture? {
        guard let visibilityGeneration = captureUITicket(), !Task.isCancelled else { return nil }
        // Checked ahead of the helper route too: the helper runs this same
        // lookup, so a fresh miss here spares the XPC hop as well.
        if isHostingWindowMissFresh(on: displayID) {
            diagLog.debug(
                "captureMenuBarHostingWindowAsync: no MenuBarAgent hosting window on display \(displayID); " +
                    "recent miss, lookup skipped"
            )
            return nil
        }
        if routesThroughCaptureService,
           let viaService = await MenuBarCaptureServiceClient.shared.captureMenuBarHostingWindow(
               displayID: displayID,
               visibilityGeneration: visibilityGeneration
           )
        {
            return viaService
        }
        let content: SCShareableContent
        do {
            content = try await getShareableContent()
        } catch {
            diagLog.error("captureMenuBarHostingWindowAsync: SCShareableContent failed: \(error)")
            return nil
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            logHostingWindowMiss(on: displayID, "display \(displayID) not found")
            return nil
        }
        let displayFrame = display.frame

        // isOnScreen is not checked: SCK reports these windows off-screen. The
        // bundle ID filter excludes per-app proxy windows; the highest
        // windowID is the most recently realized.
        let window = menuBarHostingWindowCandidates(in: content, displayFrame: displayFrame)
            .max { $0.windowID < $1.windowID }

        guard let window else {
            // No strip fallback: it includes app menus that would poison
            // thumbnails. A clean miss lets callers use app icons.
            logHostingWindowMiss(on: displayID, "no MenuBarAgent hosting window on display \(displayID)")
            return nil
        }
        clearHostingWindowMiss(on: displayID)

        // The scale comes from the display, not a ScreenCaptureKit filter:
        // building that filter trips a SkyLight assertion and aborts the helper.
        let reportedScale = displayPixelScale(displayID)

        // SkyLight first: it takes the window's own contents, where SCK shreds
        // off-screen Liquid Glass into columns.
        if let skyLightImage = Bridging.captureWindowsImage(
            windowIDs: [window.windowID],
            options: [.boundsIgnoreFraming, .bestResolution]
        ),
            let normalized = normalizedHostingCapture(
                image: skyLightImage,
                windowFrame: window.frame,
                displayFrame: displayFrame,
                reportedScale: reportedScale
            )
        {
            diagLog.debug(
                "captureMenuBarHostingWindowAsync: SkyLight took wid=\(window.windowID) " +
                    "\(skyLightImage.width)×\(skyLightImage.height)px scale=\(normalized.scale); " +
                    "ScreenCaptureKit not consulted"
            )
            return normalized
        }

        guard desktopIndependentWindowCaptureEnabled else {
            diagLog.debug(
                "captureMenuBarHostingWindowAsync: SkyLight declined wid=\(window.windowID) and the " +
                    "ScreenCaptureKit window filter is disabled in this process"
            )
            return nil
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let pixelSize = hostingCapturePixelSize(
            windowFrame: window.frame,
            displayFrame: displayFrame,
            reportedScale: reportedScale
        )

        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureDynamicRange = .SDR
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height

        do {
            // Not Sendable, but built locally and used by exactly one call.
            nonisolated(unsafe) let filter = filter
            nonisolated(unsafe) let configuration = configuration
            let image = try await withAbandoningTimeout(Self.screenshotTimeout) {
                guard isCaptureUITicketCurrent(visibilityGeneration) else { throw CancellationError() }
                return try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            }
            guard isCaptureUITicketCurrent(visibilityGeneration) else { return nil }
            guard let normalized = normalizedHostingCapture(
                image: image,
                windowFrame: window.frame,
                displayFrame: displayFrame,
                reportedScale: reportedScale
            ) else {
                diagLog.warning(
                    "captureMenuBarHostingWindowAsync: rejected unnormalizable capture " +
                        "\(image.width)×\(image.height)px frame=\(window.frame) " +
                        "display=\(displayFrame) reportedScale=\(reportedScale)"
                )
                return nil
            }
            diagLog.debug(
                "captureMenuBarHostingWindowAsync: captured \(image.width)×\(image.height)px " +
                    "(wid=\(window.windowID)) scale=\(normalized.scale) " +
                    "pointFrame=\(normalized.windowFrame) for displayID=\(displayID)"
            )
            return normalized
        } catch is TaskTimeoutError {
            diagLog.error(
                "captureMenuBarHostingWindowAsync: SCScreenshotManager.captureImage timed out after \(Self.screenshotTimeout.components.seconds)s"
            )
            return nil
        } catch is CancellationError {
            // Debug, not error: cancellation is how a superseded capture retires.
            diagLog.debug("captureMenuBarHostingWindowAsync: capture cancelled; superseded")
            return nil
        } catch {
            diagLog.error("captureMenuBarHostingWindowAsync: SCScreenshotManager.captureImage failed: \(error)")
            return nil
        }
    }

    /// Records the miss and logs it once at warning; the same miss repeating
    /// every tick is expected and goes to debug.
    private static func logHostingWindowMiss(on displayID: CGDirectDisplayID, _ detail: String) {
        let message = "captureMenuBarHostingWindowAsync: \(detail)"
        if recordHostingWindowMiss(on: displayID) {
            diagLog.warning(message)
        } else {
            diagLog.debug(message)
        }
    }
}
