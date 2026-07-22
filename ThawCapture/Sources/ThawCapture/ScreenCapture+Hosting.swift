//
//  ScreenCapture+Hosting.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import MenuBarModel
import ScreenCaptureKit

public extension ScreenCapture {
    // MARK: - ScreenCaptureKit Implementation

    /// The result of capturing `MenuBarAgent`'s menu bar hosting window.
    /// `@unchecked Sendable`: the only reference-type member is `CGImage`, which
    /// is immutable and safe to read from any thread. Marking it lets the warm
    /// hosting-window stream return a buffered frame across the actor boundary.
    @available(macOS 27, *)
    struct MenuBarHostingCapture: @unchecked Sendable {
        /// The captured image of the whole menu bar (every status item
        /// composited on a transparent background, at `scale`).
        public let image: CGImage
        /// The hosting window's frame in global screen coordinates
        /// (Y-down). Subtract this origin from an item's frame to map it
        /// into the image, then multiply by `scale`.
        public let windowFrame: CGRect
        /// The pixel scale the image was captured at.
        public let scale: CGFloat
    }

    /// Whether an SCWindow frame matches the full-width menu-bar strip geometry
    /// (point-space or pixel-backed, as reported by some macOS 27 builds).
    @available(macOS 27, *)
    static func windowMatchesMenuBarStripGeometry(
        _ frame: CGRect,
        displayFrame: CGRect
    ) -> Bool {
        let pointSpace =
            frame.height <= 40
                && frame.width > displayFrame.width * 0.8
                && abs(frame.minX - displayFrame.minX) < 2
                && abs(frame.minY - displayFrame.minY) < 2
        let pixelSpace =
            frame.height > 40
                && frame.height <= 80
                && frame.width > displayFrame.width * 1.5
                && abs(frame.minX - displayFrame.minX) < 2
                && abs(frame.minY - displayFrame.minY) < 2
        return pointSpace || pixelSpace
    }

    @available(macOS 27, *)
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

    /// Whether `windowFrame` looks like backing pixels rather than points.
    ///
    /// Cropping AX point-space bounds with a pixel-backed frame (or multiplying
    /// that frame by `pointPixelScale` again) vertically half-slices every glyph.
    @available(macOS 27, *)
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
    /// When `windowFrame` is already in pixels, do **not** multiply by
    /// `reportedScale` again — that requests a 2×-too-large buffer and SCK's
    /// rescale shreds Liquid Glass glyphs into vertical columns.
    @available(macOS 27, *)
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

    /// Normalizes a hosting-window bitmap into point-space `windowFrame` + scale
    /// suitable for cropping AX bounds (also point-space).
    ///
    /// Derives scale from the bitmap whenever possible so a mismatched
    /// `pointPixelScale` cannot half-slice icons.
    @available(macOS 27, *)
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

        // Prefer the bitmap/frame ratio over `reportedScale` so crop math tracks
        // the pixels we actually received (fixes vertical half-cuts when SCK's
        // pointPixelScale drifts from the buffer).
        let scale = CGFloat(image.width) / windowFrame.width
        guard scale > 0.5, scale < 6 else {
            return nil
        }
        let expectedHeight = windowFrame.height * scale
        if abs(CGFloat(image.height) - expectedHeight) > 3 {
            // Axes disagree — fall back to the display's point width.
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

    @available(macOS 27, *)
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

    /// Point-space menu-bar strip used when third-party glyphs must be read from
    /// the on-screen display composite rather than MenuBarAgent's hosting window.
    @available(macOS 27, *)
    static func menuBarDisplayStripFrame(
        displayFrame: CGRect,
        height: CGFloat = 40
    ) -> CGRect {
        CGRect(
            x: displayFrame.minX,
            y: displayFrame.minY,
            width: displayFrame.width,
            height: min(max(height, 1), displayFrame.height)
        )
    }

    /// Captures the on-screen menu-bar band of a display (all windows composited).
    ///
    /// MenuBarAgent's private hosting window renders system modules cleanly, but
    /// third-party Liquid Glass slots in that same off-screen window often shred
    /// into vertical columns under ScreenCaptureKit. The display strip matches
    /// what the user sees — including third-party glyphs — at the cost of menu
    /// bar fill / wallpaper in the crop. Callers should knock out the near-uniform
    /// bar fill after cropping so Layout Bar tiles match clean system glyphs.
    ///
    /// - Parameter displayID: The display whose menu bar band to capture.
    /// - Returns: The strip capture, or `nil` on failure.
    @available(macOS 27, *)
    static func captureMenuBarDisplayStripAsync(
        displayID: CGDirectDisplayID
    ) async -> MenuBarHostingCapture? {
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
        let stripFrame = menuBarDisplayStripFrame(displayFrame: displayFrame)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let reportedScale = CGFloat(filter.pointPixelScale)
        let scale = max(reportedScale, 0.5)

        let configuration = SCStreamConfiguration()
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
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
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
        } catch {
            diagLog.error("captureMenuBarDisplayStripAsync: SCScreenshotManager.captureImage failed: \(error)")
            return nil
        }
    }

    /// Captures `MenuBarAgent`'s menu bar hosting window for a display.
    ///
    /// On macOS 27 every status item is composited as a subitem inside a single
    /// full-width window owned by `MenuBarAgent`. Capturing *that window*
    /// (rather than a display region) yields the icon glyphs on a fully
    /// transparent background — no menu bar fill and no wallpaper bleeding
    /// through the bar's translucency — which is a far cleaner source for
    /// per-item thumbnails. The caller crops each item out of the returned
    /// image using the item's AX frame and ``MenuBarHostingCapture/windowFrame``.
    ///
    /// - Parameter displayID: The display whose menu bar to capture.
    /// - Returns: The capture, or `nil` if the hosting window can't be found
    ///   or captured.
    @available(macOS 27, *)
    static func captureMenuBarHostingWindowAsync(
        displayID: CGDirectDisplayID
    ) async -> MenuBarHostingCapture? {
        let content: SCShareableContent
        do {
            content = try await getShareableContent()
        } catch {
            diagLog.error("captureMenuBarHostingWindowAsync: SCShareableContent failed: \(error)")
            return nil
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            diagLog.warning("captureMenuBarHostingWindowAsync: display \(displayID) not found")
            return nil
        }
        let displayFrame = display.frame

        // The hosting window: owned by MenuBarAgent, spanning the display's
        // menu bar (full width, ~menu-bar height, anchored at the display's
        // top-left). Note: `isOnScreen` is deliberately NOT checked — SCK
        // reports these composited menu bar windows as off-screen even though
        // they hold the live, rendered icons. Filtering on the MenuBarAgent
        // bundle ID excludes the per-app status-item proxy windows (which are
        // also full-width and off-screen). Prefer the highest windowID (most
        // recently realized) when more than one matches the display.
        let window = menuBarHostingWindowCandidates(in: content, displayFrame: displayFrame)
            .max { $0.windowID < $1.windowID }

        guard let window else {
            // Do not fall back to a full-display menu-bar strip. That capture
            // includes Finder/app menus and wallpaper; cropping AX status-item
            // frames from it poisons LayoutBar / IceBar thumbnails with menu
            // chrome. Prefer a clean miss so callers can fall back to app icons.
            diagLog.warning("captureMenuBarHostingWindowAsync: no MenuBarAgent hosting window on display \(displayID)")
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let reportedScale = CGFloat(filter.pointPixelScale)
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
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
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
        } catch {
            diagLog.error("captureMenuBarHostingWindowAsync: SCScreenshotManager.captureImage failed: \(error)")
            return nil
        }
    }

    // Captures a composite image of all windows below the specified window using ScreenCaptureKit.
    //
    // - Parameters:
    //   - windowID: The identifier of the window to exclude (capture everything below it).
    //   - screenBounds: The bounds to capture, specified in screen coordinates.
    //   - displayID: The display to capture from.
}
