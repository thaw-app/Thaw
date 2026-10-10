//
//  ScreenCapture.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import CoreVideo
import Foundation
import os.lock
import ScreenCaptureKit

/// A namespace for screen capture operations.
nonisolated enum ScreenCapture {
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
            static let cachedResult = OSAllocatedUnfairLock<Bool?>(initialState: nil)
        }
        if !reset, let result = Context.cachedResult.withLock({ $0 }) {
            return result
        }
        let result = checkPermissions()
        diagLog.debug("cachedCheckPermissions: computed fresh result = \(result) (reset=\(reset), wasCached=\(Context.cachedResult.withLock { $0 != nil }))")
        Context.cachedResult.withLock { $0 = result }
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        diagLog.debug("requestPermissions: requesting screen capture access")
        // CGRequestScreenCaptureAccess() is broken on newer macOS versions.
        // Use SCShareableContent.getWithCompletionHandler to trigger the
        // system screen capture permission prompt instead.
        SCShareableContent.getWithCompletionHandler { _, _ in
            // Intentionally empty: the call is only used to trigger the
            // system screen capture permission prompt.
        }
    }

    // MARK: Capture Window(s)

    // NOTE: The sync captureWindows / captureWindow use SkyLight's private
    // SLWindowListCreateImageFromArray for offscreen menu bar items. On macOS 26 SCK
    // rejects them (-3812 with a display filter, -3811 with desktopIndependentWindow).
    // SkyLight leaks one CFMutableDictionary per call, so live Hidden refresh runs it
    // in MenuBarCaptureService, which exits after a capture budget to reclaim it.
    //
    // The async variants use ScreenCaptureKit and don't leak. Use them for windows
    // within display bounds.

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
        // SkyLight instead of CGWindowListCreateImageFromArray, which is unavailable on
        // macOS 26+. SCK can't capture offscreen menu bar items or windows in other Spaces.
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
    ///   - screenBounds: The region in Core Graphics global display coordinates
    ///     (top-left origin, as `CGDisplayBounds(_:)` returns). An AppKit rect from
    ///     `NSScreen.frame` silently captures the mirrored band instead (#1033).
    ///   - displayID: The display to capture from.
    /// - Returns: The captured image, or nil if capture failed.
    static func captureScreenBelowWindow(
        excludingWindowID windowID: CGWindowID,
        screenBounds: CGRect,
        displayID: CGDirectDisplayID
    ) async throws -> CGImage? {
        let content = try await getShareableContent()

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            diagLog.warning("captureScreenBelowWindow: display not found for ID=\(displayID)")
            return nil
        }

        let excludedWindow = content.windows.first { $0.windowID == windowID }

        if excludedWindow == nil {
            diagLog.debug("captureScreenBelowWindow: window not found for ID=\(windowID), capturing full display")
        }

        let filter = if let excludedWindow {
            SCContentFilter(
                display: display,
                excludingWindows: [excludedWindow]
            )
        } else {
            SCContentFilter(display: display, excludingWindows: [])
        }

        // sourceRect is in display-local points; width/height are in pixels.
        let displayFrame = display.frame
        let scale = Double(filter.pointPixelScale)

        guard Bridging.isValidCaptureBounds(screenBounds, scale: CGFloat(scale)) else {
            diagLog.error("captureScreenBelowWindow: refusing capture with invalid screenBounds=\(screenBounds) scale=\(scale) — see issue #759")
            return nil
        }

        let localSourceRect = CGRect(
            x: screenBounds.origin.x - displayFrame.origin.x,
            y: screenBounds.origin.y - displayFrame.origin.y,
            width: screenBounds.width,
            height: screenBounds.height
        )

        let configuration = SCStreamConfiguration()
        // captureResolution is not used here; explicit width/height below take precedence.
        configuration.showsCursor = false
        // Pin 32BGRA so the buffer matches on SDR and EDR displays; an HDR display can
        // otherwise return a 10-bit buffer that renders differently. Don't set
        // `colorSpaceName`: it triggers a CoreGraphics tone-mapping pass that clips color.
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.width = Int((screenBounds.width * scale).rounded())
        configuration.height = Int((screenBounds.height * scale).rounded())
        configuration.sourceRect = localSourceRect

        // Pixel dimensions look healthy even for a mirrored band, so log the rects to
        // make a misplaced capture visible (#1033).
        diagLog.debug(
            "captureScreenBelowWindow: screenBounds=\(screenBounds.debugDescription) "
                + "displayFrame=\(displayFrame.debugDescription) "
                + "sourceRect=\(localSourceRect.debugDescription)"
        )

        // The caller owns the stream and must call stopCapture().
        let frameCaptor = FrameCaptor()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: frameCaptor)

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

    /// Shareable content via `ShareableContentCache`: calls within `maxAge` share one
    /// fetch, since one capture tick can issue several full enumerations.
    static func getShareableContent(maxAge: Duration = .milliseconds(150)) async throws -> SCShareableContent {
        let snapshot = try await shareableContentCache.content(
            maxAge: maxAge,
            fetch: fetchShareableContentUncached
        )
        return snapshot.content
    }

    private static let shareableContentCache = ShareableContentCache<ShareableContentSnapshot>()

    /// Performs the underlying enumeration for ``getShareableContent(maxAge:)``
    /// on a cache miss.
    ///
    /// No cancellation handler: `awaitWithoutCancelling` shields the shared fetch
    /// from caller cancellation, so one would never fire.
    private static func fetchShareableContentUncached() async throws -> ShareableContentSnapshot {
        let content = try await SCShareableContent.current
        return ShareableContentSnapshot(content: content)
    }
}

// MARK: - Helper Types

private final nonisolated class FrameCaptor: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
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
