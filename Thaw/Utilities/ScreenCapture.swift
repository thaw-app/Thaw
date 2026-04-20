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
            diagLog.debug("captureWindows: captured \(windowIDs.count) windows → \(image.width)×\(image.height)px")
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

    // MARK: - ScreenCaptureKit Implementation

    /// Captures a composite image of all windows below the specified window using ScreenCaptureKit.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to exclude (capture everything below it).
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///   - displayID: The display to capture from.
    /// - Returns: The captured image, or nil if capture failed.
    static func captureScreenBelowWindow(
        excludingWindowID windowID: CGWindowID,
        screenBounds: CGRect,
        displayID: CGDirectDisplayID
    ) async throws -> CGImage? {
        // Get shareable content (displays and windows)
        let content = try await getShareableContent()

        // Find the target display
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            diagLog.warning("captureScreenBelowWindow: display not found for ID=\(displayID)")
            return nil
        }

        // Find the window to exclude
        let excludedWindow = content.windows.first { $0.windowID == windowID }

        if excludedWindow == nil {
            diagLog.warning("captureScreenBelowWindow: window not found for ID=\(windowID), capturing full display")
        }

        // Create filter: include display, exclude the specified window
        let filter: SCContentFilter
        if let excludedWindow = excludedWindow {
            filter = SCContentFilter(
                display: display,
                excludingWindows: [excludedWindow]
            )
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // Configure stream for single frame capture
        let configuration = SCStreamConfiguration()
        configuration.captureResolution = .automatic
        configuration.showsCursor = false
        configuration.width = Int(screenBounds.width)
        configuration.height = Int(screenBounds.height)
        configuration.sourceRect = screenBounds

        // Create stream and capture frame
        let frameCaptor = FrameCaptor()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: frameCaptor)

        try await stream.startCapture()

        // Wait for frame with timeout
        let image = try await withTimeout(seconds: 5) {
            await frameCaptor.waitForFrame()
        }

        try await stream.stopCapture()

        if let image {
            diagLog.debug("captureScreenBelowWindow: captured below windowID=\(windowID) → \(image.width)×\(image.height)px")
        } else {
            diagLog.warning("captureScreenBelowWindow: failed to capture image below windowID=\(windowID)")
        }

        return image
    }

    /// Helper to get shareable content using async wrapper
    private static func getShareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getWithCompletionHandler { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: ScreenCaptureError.noContent)
                }
            }
        }
    }
}

// MARK: - Helper Types

private enum ScreenCaptureError: Error {
    case noContent
}

/// Helper class to capture frames from SCStream
private final class FrameCaptor: NSObject, SCStreamOutput, SCStreamDelegate {
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private let lock = NSLock()

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else {
            resume(with: nil)
            return
        }

        // Convert CVImageBuffer to CGImage
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            resume(with: nil)
            return
        }

        resume(with: cgImage)
    }

    func stream(_: SCStream, didStopWithError _: Error) {
        resume(with: nil)
    }

    private func resume(with image: CGImage?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: image)
    }

    func waitForFrame() async -> CGImage? {
        await withCheckedContinuation { cont in
            lock.lock()
            self.continuation = cont
            lock.unlock()
        }
    }
}

/// Helper to add timeout to async operations
private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        guard let result = try await group.next() else {
            group.cancelAll()
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {}
