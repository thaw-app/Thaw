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
        // CGRequestScreenCaptureAccess() is broken on macOS 15+. We can
        // try accessing SCShareableContent to trigger a request if the
        // user doesn't have permissions.
        SCShareableContent.getWithCompletionHandler { _, _ in
            // Intentionally empty: the call is only used to trigger the
            // system screen capture permission prompt on macOS 15+.
        }
    }

    // MARK: Capture Window(s)

    // NOTE: We intentionally use the deprecated CGWindowList API here instead of
    // ScreenCaptureKit. SCShareableContent only returns on-screen windows in the
    // current Space, but we need to capture:
    //   - Offscreen menu bar items (overflow area)
    //   - Windows in other Spaces
    //   - Windows partially clipped by screen edges
    //
    // This is an architectural limitation of ScreenCaptureKit (designed for
    // screen recording/streaming, not arbitrary window capture), not a bug.
    // Even macOS 15+ does not provide public APIs to enumerate offscreen windows.
    //
    // CGWindowList remains the only public API capable of accessing offscreen
    // and cross-Space window content. We use the hybrid approach:
    // ScreenCaptureKit for display capture, CGWindowList for window capture.

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
        // Use SkyLight's private API (SLWindowListCreateImageFromArray) instead of
        // the deprecated CGWindowListCreateImageFromArray, which is unavailable
        // when targeting macOS 26+. ScreenCaptureKit still doesn't support
        // capturing offscreen menu bar items or windows in other Spaces.
        return Bridging.captureWindowsImage(windowIDs: windowIDs, screenBounds: screenBounds, options: option)
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
            diagLog.debug("captureScreenBelowWindow: window not found for ID=\(windowID), capturing full display")
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

        // Configure stream for single frame capture.
        // sourceRect is in display-local points; width/height are in pixels.
        let displayFrame = display.frame
        let scale = Double(filter.pointPixelScale)

        let localSourceRect = CGRect(
            x: screenBounds.origin.x - displayFrame.origin.x,
            y: screenBounds.origin.y - displayFrame.origin.y,
            width: screenBounds.width,
            height: screenBounds.height
        )

        let configuration = SCStreamConfiguration()
        // captureResolution is not used here; explicit width/height below take precedence.
        configuration.showsCursor = false
        configuration.width = Int((screenBounds.width * scale).rounded())
        configuration.height = Int((screenBounds.height * scale).rounded())
        configuration.sourceRect = localSourceRect

        // Create stream and capture frame
        // Note: Caller owns the stream and is responsible for stopCapture().
        let frameCaptor = FrameCaptor()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: frameCaptor)

        // Register FrameCaptor to receive sample buffers
        try stream.addStreamOutput(frameCaptor, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.stonerl.Thaw.screencapture"))

        try await stream.startCapture()

        // Wait for frame with timeout, ensuring stopCapture() always called
        let image: CGImage?
        do {
            image = try await withTimeout(seconds: 5) {
                await frameCaptor.waitForFrame()
            }
            try? await stream.stopCapture()
        } catch {
            try? await stream.stopCapture()
            throw error
        }

        if let image {
            diagLog.debug("captureScreenBelowWindow: captured below windowID=\(windowID) → \(image.width)×\(image.height)px")
        } else {
            diagLog.warning("captureScreenBelowWindow: failed to capture image below windowID=\(windowID)")
        }

        return image
    }

    /// Helper to get shareable content using async wrapper
    private static func getShareableContent() async throws -> SCShareableContent {
        let box = ContinuationBox<SCShareableContent, any Error>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.setContinuation(continuation)
                SCShareableContent.getWithCompletionHandler { content, error in
                    guard let continuation = box.takeContinuation() else { return }
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let content {
                        continuation.resume(returning: content)
                    } else {
                        continuation.resume(throwing: ScreenCaptureError.noContent)
                    }
                }
            }
        } onCancel: {
            // Resume with cancellation error if still pending
            if let continuation = box.takeContinuation() {
                continuation.resume(throwing: CancellationError())
            }
        }
    }
}

// MARK: - Helper Types

private enum ScreenCaptureError: Error {
    case noContent
}

/// Helper class to capture frames from SCStream
/// Thread-safe box for storing and retrieving a continuation across concurrent contexts
private final class ContinuationBox<T, E: Error>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, E>?
    private let lock = NSLock()

    func setContinuation(_ cont: CheckedContinuation<T, E>) {
        lock.lock()
        continuation = cont
        lock.unlock()
    }

    /// Returns and clears the continuation atomically, or nil if already taken
    func takeContinuation() -> CheckedContinuation<T, E>? {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        return cont
    }
}

private final class FrameCaptor: NSObject, SCStreamOutput, SCStreamDelegate {
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var bufferedImage: CGImage?
    private var stream: SCStream?
    private let lock = NSLock()

    func setStream(_ stream: SCStream) {
        lock.lock()
        self.stream = stream
        lock.unlock()
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else {
            resumeOrBuffer(with: nil)
            return
        }

        // Convert CVImageBuffer to CGImage
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            resumeOrBuffer(with: nil)
            return
        }

        resumeOrBuffer(with: cgImage)
    }

    func stream(_: SCStream, didStopWithError _: Error) {
        resumeOrBuffer(with: nil)
    }

    private func resumeOrBuffer(with image: CGImage?) {
        lock.lock()
        if let cont = continuation {
            continuation = nil
            stream = nil
            lock.unlock()
            cont.resume(returning: image)
        } else {
            bufferedImage = image
            lock.unlock()
        }
    }

    func waitForFrame() async -> CGImage? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                lock.lock()
                // Check if frame already buffered
                if let image = bufferedImage {
                    bufferedImage = nil
                    lock.unlock()
                    cont.resume(returning: image)
                    return
                }
                // Otherwise, install continuation
                self.continuation = cont
                lock.unlock()
            }
        } onCancel: { [weak self] in
            self?.stopStreamAndResume()
        }
    }

    private func stopStreamAndResume() {
        lock.lock()
        let cont = continuation
        continuation = nil
        stream = nil
        lock.unlock()

        // Resume with nil on cancellation; caller remains responsible for stopCapture().
        cont?.resume(returning: nil)
    }
}

/// Helper to add timeout to async operations
private func withTimeout<T>(seconds: TimeInterval, operation: sending @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        // group.next() returning nil is unreachable in this context (always at least one task),
        // but the guard serves as defensive documentation.
        guard let result = try await group.next() else {
            group.cancelAll()
            throw TimeoutError()
        }
        group.cancelAll()
        return result
    }
}

private struct TimeoutError: Error {}
