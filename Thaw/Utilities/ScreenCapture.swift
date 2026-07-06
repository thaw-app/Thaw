//
//  ScreenCapture.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreGraphics
import Foundation
import os.lock
@preconcurrency import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {
    private static let diagLog = DiagLog(category: "ScreenCapture")
    private static let cachedPermissionResult = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    static func checkPermissions() -> Bool {
        let windowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        diagLog.debug("checkPermissions: checking \(windowIDs.count) menu bar window(s) for title access")
        var windowTitles = [String?]()

        for windowID in windowIDs {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            let hasTitle = window.title != nil
            diagLog.debug("checkPermissions: windowID=\(windowID) pid=\(window.ownerPID) owner=\"\(window.ownerName ?? "nil")\" title=\"\(window.title ?? "nil")\" → hasTitle=\(hasTitle)")
            windowTitles.append(window.title)
        }

        let preflightResult = CGPreflightScreenCaptureAccess()
        let result = permissionGranted(
            windowTitles: windowTitles,
            preflightResult: preflightResult
        )
        diagLog.debug("checkPermissions: titledWindow=\(windowTitles.contains { $0 != nil }), CGPreflightScreenCaptureAccess()=\(preflightResult) → \(result)")
        return result
    }

    /// Resolves screen capture access from all eligible window titles and the
    /// Core Graphics preflight result. A single untitled window must not mask
    /// a later titled window that proves access.
    static func permissionGranted(
        windowTitles: [String?],
        preflightResult: Bool
    ) -> Bool {
        preflightResult || windowTitles.contains { $0 != nil }
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent
    /// calls. Pass `true` to the `reset` parameter to replace the cached
    /// result with a newly computed value.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        if !reset, let result = cachedPermissionResult.withLock({ $0 }) {
            return result
        }
        let result = checkPermissions()
        diagLog.debug("cachedCheckPermissions: computed fresh result = \(result) (reset=\(reset), wasCached=\(cachedPermissionResult.withLock { $0 != nil }))")
        cachedPermissionResult.withLock { $0 = result }
        return result
    }

    private static func setCachedPermissionResult(_ result: Bool?) {
        cachedPermissionResult.withLock { $0 = result }
    }

    static func restoreActivationPolicyAfterScreenCapturePrompt(
        currentPolicy: NSApplication.ActivationPolicy,
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool,
        activate: () -> Void
    ) -> (() -> Void)? {
        guard currentPolicy != .regular else {
            activate()
            return nil
        }

        _ = setActivationPolicy(.regular)
        activate()

        return {
            _ = setActivationPolicy(currentPolicy)
        }
    }

    /// Requests screen capture permissions.
    @MainActor
    static func requestPermissions() {
        diagLog.debug("requestPermissions: requesting screen capture access")
        setCachedPermissionResult(nil)

        // Thaw is an LSUIElement (agent) app with no Dock icon. The system
        // permission prompt for Screen Recording is only reliably surfaced
        // — and the app only reliably registered in System Settings' list —
        // when the requesting process is a normal frontmost app. Temporarily
        // switch out of agent mode for the request, then restore it after the
        // TCC request has been kicked off.
        let restoreActivationPolicy = restoreActivationPolicyAfterScreenCapturePrompt(
            currentPolicy: NSApp.activationPolicy(),
            setActivationPolicy: { NSApp.setActivationPolicy($0) },
            activate: { NSApp.activate(ignoringOtherApps: true) }
        )

        // CGRequestScreenCaptureAccess() was reported broken on macOS 15
        // (didn't reliably prompt), so this used to rely solely on
        // SCShareableContent to trigger the prompt. On macOS 27 that alone
        // has been observed to leave the app entirely absent from the
        // Screen Recording list, even after the call completes and even
        // after a full relaunch. Call both: CGRequestScreenCaptureAccess()
        // is the documented public API for adding an app to that list, and
        // SCShareableContent is kept as a fallback trigger.
        let cgResult = CGRequestScreenCaptureAccess()
        if cgResult {
            setCachedPermissionResult(true)
        }
        diagLog.debug("requestPermissions: CGRequestScreenCaptureAccess() = \(cgResult)")

        SCShareableContent.getWithCompletionHandler { content, error in
            if let error {
                diagLog.debug("requestPermissions: SCShareableContent request failed: \(error)")
            } else {
                setCachedPermissionResult(true)
                diagLog.debug("requestPermissions: SCShareableContent request succeeded (\(content?.windows.count ?? 0) windows)")
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            restoreActivationPolicy?()
        }
    }

    // MARK: Capture Window(s)

    // NOTE: The synchronous captureWindows / captureWindow below intentionally
    // route through the deprecated SkyLight private API
    // (SLWindowListCreateImageFromArray) for the menu-bar refresh path. On
    // macOS 26 SCShareableContent.excludingDesktopWindows(_: onScreenWindowsOnly:
    // false) *does* enumerate offscreen menu-bar overflow items, but SCK
    // capture rejects them: SCContentFilter(display: including:) returns error
    // -3812 (sourceRect outside display bounds) and SCContentFilter(
    // desktopIndependentWindow:) returns -3811 (stream start failure). SkyLight
    // is the only public API on macOS 26 that can capture status-item windows
    // positioned at large negative x. It leaks one CFMutableDictionary per
    // call inside SLSWindowListCreateImageFromArrayProxying; that's a system
    // bug awaiting an Apple fix.
    //
    // The async captureWindowsAsync / captureWindowAsync below route through
    // ScreenCaptureKit and are leak-free. Use those for any capture whose
    // windows fit within display bounds (the menu-bar item cache paths
    // pre-filter offscreen items and use the async path).

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

    // MARK: Capture Window(s) via ScreenCaptureKit

    /// Async, ScreenCaptureKit-backed equivalent of captureWindows. Leak-free,
    /// but the underlying SCK filter is display-bounded; use captureWindows
    /// (SkyLight) for windows positioned off-display.
    static func captureWindowsAsync(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) async -> CGImage? {
        await Bridging.captureWindowsImageSCK(windowIDs: windowIDs, screenBounds: screenBounds, options: option)
    }

    /// Async, ScreenCaptureKit-backed equivalent of captureWindow.
    static func captureWindowAsync(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) async -> CGImage? {
        await captureWindowsAsync(with: [windowID], screenBounds: screenBounds, option: option)
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
        let filter = if let excludedWindow {
            SCContentFilter(
                display: display,
                excludingWindows: [excludedWindow]
            )
        } else {
            SCContentFilter(display: display, excludingWindows: [])
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

        // Register FrameCaptor to receive sample buffers using shared serial queue
        try stream.addStreamOutput(frameCaptor, type: .screen, sampleHandlerQueue: FrameCaptor.sampleHandlerQueue)

        try await stream.startCapture()

        // Wait for frame with timeout, ensuring stopCapture() always called
        let image: CGImage?
        do {
            image = try await Task<CGImage?, any Error>.withTimeout(.seconds(5), tolerance: nil, clock: .continuous) {
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
                SCShareableContent.getWithCompletionHandler(makeShareableContentCompletion(box: box))
            }
        } onCancel: {
            // Resume with cancellation error if still pending
            if let continuation = box.takeContinuation() {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    /// Creates a completion handler for SCShareableContent request
    private static func makeShareableContentCompletion(
        box: ContinuationBox<SCShareableContent, any Error>
    ) -> @Sendable (SCShareableContent?, Error?) -> Void {
        { content, error in
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
}

// MARK: - Helper Types

private enum ScreenCaptureError: Error {
    case noContent
}

private final class ContinuationBox<T, E: Error>: Sendable {
    private let lock = OSAllocatedUnfairLock<CheckedContinuation<T, E>?>(initialState: nil)

    func setContinuation(_ cont: CheckedContinuation<T, E>) {
        lock.withLock { $0 = cont }
    }

    func takeContinuation() -> CheckedContinuation<T, E>? {
        lock.withLock { $0.take() }
    }
}

private final class FrameCaptor: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Shared serial queue for all SCStream sample buffer handlers.
    static let sampleHandlerQueue = DispatchQueue(label: "com.stonerl.Thaw.screencapture")

    /// Reused across frames to avoid repeated GPU/Metal setup costs.
    private let ciContext = CIContext()

    private let lock = OSAllocatedUnfairLock<(continuation: CheckedContinuation<CGImage?, Never>?, bufferedImage: CGImage?)>(initialState: (nil, nil))

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusInt = attachments.first?[SCStreamFrameInfo.status] as? Int,
              let frameStatus = SCFrameStatus(rawValue: statusInt),
              frameStatus == .complete
        else {
            return
        }

        guard let imageBuffer = sampleBuffer.imageBuffer else {
            resumeOrBuffer(with: nil)
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            resumeOrBuffer(with: nil)
            return
        }

        resumeOrBuffer(with: cgImage)
    }

    func stream(_: SCStream, didStopWithError _: Error) {
        resumeOrBuffer(with: nil)
    }

    private func resumeOrBuffer(with image: CGImage?) {
        let cont = lock.withLock { state -> CheckedContinuation<CGImage?, Never>? in
            if let c = state.continuation {
                state.continuation = nil
                return c
            }
            state.bufferedImage = image
            return nil
        }
        if let cont {
            cont.resume(returning: image)
        }
    }

    func waitForFrame() async -> CGImage? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                claimOrRegister(cont: cont)
            }
        } onCancel: { [weak self] in
            self?.cancelPendingWait()
        }
    }

    private func claimOrRegister(cont: CheckedContinuation<CGImage?, Never>) {
        let (image, shouldResume) = lock.withLock { state -> (CGImage?, Bool) in
            if let image = state.bufferedImage {
                state.bufferedImage = nil
                return (image, true)
            }
            if Task.isCancelled {
                return (nil, true)
            }
            state.continuation = cont
            return (nil, false)
        }
        if shouldResume {
            cont.resume(returning: image)
        }
    }

    private func cancelPendingWait() {
        let cont = lock.withLock { state -> CheckedContinuation<CGImage?, Never>? in
            let c = state.continuation
            state.continuation = nil
            return c
        }
        cont?.resume(returning: nil)
    }
}
