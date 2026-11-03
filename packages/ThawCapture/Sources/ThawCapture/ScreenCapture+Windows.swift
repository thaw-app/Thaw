//
//  ScreenCapture+Windows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel

public extension ScreenCapture {
    // MARK: Capture Window(s)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited front to back, in the order of windowIDs.
    ///
    /// ScreenCaptureKit's content filter is bounded by the display: a window
    /// outside display bounds fails the capture with -3812 for a display
    /// filter and -3811 for a window one. That holds for everything Thaw
    /// captures, since status items have no WindowServer windows of their own
    /// and the item cache filters concealed items off this path.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass nil to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(
        with windowIDs: [CGWindowID],
        screenBounds: CGRect? = nil,
        option: CGWindowImageOption = []
    ) async -> CGImage? {
        guard let ticket = captureUITicket(), !Task.isCancelled else { return nil }
        if routesThroughCaptureService,
           let viaService = await MenuBarCaptureServiceClient.shared.captureWindows(
               with: windowIDs,
               screenBounds: screenBounds,
               option: option,
               visibilityGeneration: ticket
           )
        {
            return viaService
        }
        let image = await Bridging.captureWindowsImageSCK(windowIDs: windowIDs, screenBounds: screenBounds, options: option, shouldCapture: { isCaptureUITicketCurrent(ticket) })
        return isCaptureUITicketCurrent(ticket) ? image : nil
    }
}
