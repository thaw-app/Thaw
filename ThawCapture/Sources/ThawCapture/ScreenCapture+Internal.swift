//
//  ScreenCapture+Internal.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import os.lock
import ScreenCaptureKit

extension ScreenCapture {
    /// - Returns: The captured image, or nil if capture failed.
    public static func captureScreenBelowWindow(
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
        // Pin the pixel format so the buffer is deterministic across SDR/EDR
        // displays. Left unset, an HDR display can hand back a 10-bit buffer that
        // the CIImage → CGImage conversion renders subtly differently, an
        // intermittent display-dependent color glitch. 32BGRA is the historical
        // default and what the crop/compare path expects. Do NOT set
        // `colorSpaceName` — it triggers an internal CoreGraphics tone-mapping
        // pass that destructively clips color (learned from BetterCapture).
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
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

    /// Helper to get shareable content using ScreenCaptureKit's async API.
    ///
    /// One capture tick issues 2-3 independent calls (hosting-window capture,
    /// display-strip capture, the hosting frame probe), each a full
    /// window/display enumeration. `ShareableContentCache` coalesces calls
    /// within `maxAge` of each other into a single underlying fetch.
    static func getShareableContent(maxAge: Duration = .milliseconds(150)) async throws -> SCShareableContent {
        let snapshot = try await shareableContentCache.content(
            maxAge: maxAge,
            fetch: fetchShareableContentUncached
        )
        return snapshot.content
    }

    private static let shareableContentCache = ShareableContentCache()

    /// `SCShareableContent.current` is the async form of
    /// `getShareableContentWithCompletionHandler:`. It has no built-in
    /// cancellation, so it runs inside a child task that races a
    /// `withTaskCancellationHandler` resume: a cancelled caller aborts promptly
    /// instead of proceeding to a wasted capture, while a late framework result
    /// is discarded because the continuation has already been taken.
    private static func fetchShareableContentUncached() async throws -> ShareableContentSnapshot {
        let box = ContinuationBox<SCShareableContent, any Error>()
        let content = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.setContinuation(continuation)
                Task {
                    do {
                        let content = try await SCShareableContent.current
                        box.takeContinuation()?.resume(returning: content)
                    } catch {
                        box.takeContinuation()?.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            // Resume with cancellation error if still pending.
            box.takeContinuation()?.resume(throwing: CancellationError())
        }
        return ShareableContentSnapshot(content: content)
    }
}

/// Coalesces concurrent/rapid `getShareableContent()` calls into one fetch.
///
/// Holds the most recent result plus an in-flight fetch task. Callers that
/// arrive while a fetch is already running await that same task rather than
/// starting a second enumeration; only the caller that started the task
/// records the result and clears `inFlightTask`, so joiners never race each
/// other over cache bookkeeping.
actor ShareableContentCache {
    private var cached: (content: ShareableContentSnapshot, timestamp: ContinuousClock.Instant)?
    private var inFlightTask: Task<ShareableContentSnapshot, any Error>?

    fileprivate func content(
        maxAge: Duration,
        fetch: @Sendable @escaping () async throws -> ShareableContentSnapshot
    ) async throws -> ShareableContentSnapshot {
        if let cached, ContinuousClock.now - cached.timestamp < maxAge {
            return cached.content
        }

        if let inFlightTask {
            return try await awaitWithoutCancelling(inFlightTask)
        }

        let task = Task<ShareableContentSnapshot, any Error> {
            try await fetch()
        }
        inFlightTask = task
        do {
            let content = try await awaitWithoutCancelling(task)
            cached = (content, .now)
            inFlightTask = nil
            return content
        } catch {
            inFlightTask = nil
            throw error
        }
    }

    /// A caller cancelling must not cancel the shared task — other callers
    /// may still be awaiting its result.
    private func awaitWithoutCancelling(
        _ task: Task<ShareableContentSnapshot, any Error>
    ) async throws -> ShareableContentSnapshot {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {}
    }
}

/// An immutable ScreenCaptureKit snapshot passed across the cache actor.
///
/// `SCShareableContent` is an Objective-C reference type without a Sendable
/// annotation. It is returned as a completed framework snapshot and this
/// wrapper never mutates or exposes any mutable state, so sharing that
/// reference among the capture readers is safe.
private struct ShareableContentSnapshot: @unchecked Sendable {
    let content: SCShareableContent
}

// MARK: - Helper Types

enum ScreenCaptureError: Error {
    case noContent
}

final class ContinuationBox<T, E: Error>: Sendable {
    private let lock = OSAllocatedUnfairLock<CheckedContinuation<T, E>?>(initialState: nil)

    func setContinuation(_ cont: CheckedContinuation<T, E>) {
        lock.withLock { $0 = cont }
    }

    func takeContinuation() -> CheckedContinuation<T, E>? {
        lock.withLock { $0.take() }
    }
}

/// `SCStream` delivers `stream(_:didOutputSampleBuffer:of:)`/
/// `stream(_:didStopWithError:)` callbacks on `sampleHandlerQueue`, a
/// background serial queue — not on any actor. `ciContext` just returns the
/// `static let sharedCIContext`, an immutable, process-wide `CIContext`. The
/// only mutable state (`continuation`, `bufferedImage`) lives in `lock`, an
/// `OSAllocatedUnfairLock`, and is only ever read or written under that
/// lock, which is how the background-queue callback safely hands a frame
/// back to the awaiting caller.
final class FrameCaptor: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Shared serial queue for all SCStream sample buffer handlers.
    static let sampleHandlerQueue = DispatchQueue(label: "com.stonerl.Thaw.screencapture")

    /// Process-wide `CIContext`, shared across every capture. A `CIContext`
    /// allocates a Metal device and command queue; `FrameCaptor` is created per
    /// capture, so a per-instance context paid that GPU/Metal setup on every
    /// single capture. One shared context amortizes it across the whole app.
    static let sharedCIContext = CIContext()

    private var ciContext: CIContext {
        FrameCaptor.sharedCIContext
    }

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

// MARK: - Task Timeout

/// An error indicates task timed out.
struct TaskTimeoutError: CustomStringConvertible, LocalizedError {
    let description = "Task timed out before completion"

    var errorDescription: String? {
        description
    }
}

extension Task {
    static func withTimeout<C: Clock>(
        _ timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        operation: @escaping @Sendable () async throws -> Success
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await _Concurrency.Task.sleep(for: timeout, tolerance: tolerance, clock: clock)
                throw TaskTimeoutError()
            }
            guard let success = try await group.next() else {
                throw _Concurrency.CancellationError()
            }
            group.cancelAll()
            return success
        }
    }
}
