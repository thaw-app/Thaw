//
//  ScreenCapture.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {
    private static let diagLog = DiagLog(category: "ScreenCapture")

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    static func checkPermissions() -> Bool {
        let windowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        diagLog.debug("checkPermissions: checking \(windowIDs.count) menu bar window(s) for title access")

        for windowID in windowIDs {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            let hasTitle = window.title != nil
            diagLog.debug("checkPermissions: windowID=\(windowID) pid=\(window.ownerPID) owner=\"\(window.ownerName ?? "nil")\" title=\"\(window.title ?? "nil")\" → hasTitle=\(hasTitle)")
            return hasTitle
        }
        // CGPreflightScreenCaptureAccess() only returns an initial value,
        // but we can use it as a fallback.
        let preflightResult = CGPreflightScreenCaptureAccess()
        diagLog.debug("checkPermissions: no suitable non-owned windows found, fallback CGPreflightScreenCaptureAccess() → \(preflightResult)")
        return preflightResult
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent
    /// calls. Pass `true` to the `reset` parameter to replace the cached
    /// result with a newly computed value.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        enum Context {
            static var cachedResult: Bool?
        }
        if !reset, let result = Context.cachedResult {
            return result
        }
        let result = checkPermissions()
        diagLog.debug("cachedCheckPermissions: computed fresh result = \(result) (reset=\(reset), wasCached=\(Context.cachedResult != nil))")
        Context.cachedResult = result
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        diagLog.debug("requestPermissions: requesting screen capture access")
        if #available(macOS 15.0, *) {
            // CGRequestScreenCaptureAccess() is broken on macOS 15. We can
            // try accessing SCShareableContent to trigger a request if the
            // user doesn't have permissions.
            // Workaround: CGRequestScreenCaptureAccess() is broken on macOS 15+.
            SCShareableContent.getWithCompletionHandler { _, _ in
                // Intentionally empty: the call is only used to trigger the
                // system screen capture permission prompt on macOS 15+.
            }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Capture Window(s)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited from front to back, according to the order
    /// of the `windowIDs` parameter.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            diagLog.warning("captureWindows: createCGWindowArray returned nil for \(windowIDs.count) window IDs")
            return nil
        }
        let bounds = screenBounds ?? .null
        let boundsDesc = bounds.isNull ? "null (auto)" : String(format: "(%.0f,%.0f %.0fx%.0f)", bounds.origin.x, bounds.origin.y, bounds.width, bounds.height)
        diagLog.debug("captureWindows: bounds=\(boundsDesc), windowCount=\(windowIDs.count), options=\(option.rawValue)")
        // ScreenCaptureKit doesn't support capturing images of offscreen menu bar
        // items, so we unfortunately have to use the deprecated CGWindowList API.
        let image = CGImage(windowListFromArrayScreenBounds: bounds, windowArray: array as CFArray, imageOption: option)
        if let image {
            diagLog.debug("captureWindows: ✓ captured \(windowIDs.count) windows → \(image.width)×\(image.height)px")
        } else {
            diagLog.warning("captureWindows: CGImage(windowListFromArrayScreenBounds:) returned nil for \(windowIDs.count) windows (IDs: \(windowIDs.prefix(5)))")
        }
        return image
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify which parts of the window are captured.
    static func captureWindow(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows(with: [windowID], screenBounds: screenBounds, option: option)
    }

    /// Captures a composite image of all windows below the specified window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture below.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureScreenBelowWindow(with windowID: CGWindowID, screenBounds: CGRect, option: CGWindowImageOption = []) -> CGImage? {
        let image = CGWindowListCreateImage(screenBounds, .optionOnScreenBelowWindow, windowID, option)
        if let image {
            diagLog.debug("captureScreenBelowWindow: ✓ captured below windowID=\(windowID) → \(image.width)×\(image.height)px")
        } else {
            diagLog.warning("captureScreenBelowWindow: CGWindowListCreateImage returned nil for windowID=\(windowID)")
        }
        return image
    }
}
