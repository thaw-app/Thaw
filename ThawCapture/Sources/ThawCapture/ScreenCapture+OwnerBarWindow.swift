//
//  ScreenCapture+OwnerBarWindow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

public extension ScreenCapture {
    /// Capture app-owned bar windows absent from MenuBarAgent and unaddressable by SCK; frame uses global coordinates.
    /// SkyLight accepts their window IDs; route through the service to contain its per-call leak in the helper.
    static func captureOwnerBarWindow(
        windowID: CGWindowID,
        frame: CGRect
    ) async -> MenuBarHostingCapture? {
        guard let ticket = captureUITicket(), !Task.isCancelled, frame.width > 0 else { return nil }
        if routesThroughCaptureService,
           let viaService = await MenuBarCaptureServiceClient.shared.captureOwnerBarWindow(
               windowID: windowID,
               visibilityGeneration: ticket
           )
        {
            return viaService
        }
        guard let capture = ownerBarWindowCapture(windowID: windowID, frame: frame) else { return nil }
        return isCaptureUITicketCurrent(ticket) ? capture : nil
    }

    /// Read and validate the server's frame, not a caller-supplied one, to refuse arbitrary-window captures.
    /// Only display-top, bar-height strips spanning the display qualify.
    static func captureOwnerBarWindowForService(windowID: CGWindowID) -> MenuBarHostingCapture? {
        guard let frame = Bridging.getWindowBounds(for: windowID), isMenuBarStripFrame(frame) else {
            diagLog.warning("captureOwnerBarWindowForService: window \(windowID) is not a menu bar strip")
            return nil
        }
        return ownerBarWindowCapture(windowID: windowID, frame: frame)
    }

    private static func ownerBarWindowCapture(windowID: CGWindowID, frame: CGRect) -> MenuBarHostingCapture? {
        guard frame.width > 0, let image = Bridging.captureWindowsImage(
            windowIDs: [windowID],
            options: [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }
        return MenuBarHostingCapture(
            image: image,
            windowFrame: frame,
            scale: CGFloat(image.width) / frame.width
        )
    }

    /// Require at least 80% display width, at most 60 pt height, and top-edge alignment.
    static func isMenuBarStripFrame(_ frame: CGRect, in displayBounds: CGRect) -> Bool {
        guard frame.height > 0, frame.height <= 60 else { return false }
        return frame.width >= displayBounds.width * 0.8
            && abs(frame.minY - displayBounds.minY) <= 1
            && frame.minX >= displayBounds.minX - 1
            && frame.maxX <= displayBounds.maxX + 1
    }

    private static func isMenuBarStripFrame(_ frame: CGRect) -> Bool {
        guard frame.height > 0, frame.height <= 60 else { return false }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains {
            isMenuBarStripFrame(frame, in: CGDisplayBounds($0))
        }
    }
}
