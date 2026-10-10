//
//  ScreenCapture+Internal.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import os.lock
import ScreenCaptureKit

extension ScreenCapture {
    /// Helper to get shareable content using ScreenCaptureKit's async API.
    ///
    /// One capture tick issues 2-3 independent calls (hosting-window capture,
    /// display-strip capture, the hosting frame probe), each a full
    /// window/display enumeration. ShareableContentCache coalesces calls
    /// within maxAge of each other into a single underlying fetch.
    static func getShareableContent(maxAge: Duration = .milliseconds(150)) async throws -> SCShareableContent {
        let snapshot = try await shareableContentCache.content(
            maxAge: maxAge,
            fetch: fetchShareableContentUncached
        )
        return snapshot.content
    }

    private static let shareableContentCache = ShareableContentCache()

    /// SCShareableContent.current has neither cancellation nor a deadline, so
    /// it runs abandoned-on-timeout: a cancelled caller aborts promptly, and a
    /// fetch that never answers fails after the screenshot timeout. Without
    /// the deadline one stuck fetch would park every later capture, since
    /// ShareableContentCache joins callers to the fetch in flight.
    private static func fetchShareableContentUncached() async throws -> ShareableContentSnapshot {
        try await withAbandoningTimeout(screenshotTimeout) {
            try await ShareableContentSnapshot(content: SCShareableContent.current)
        }
    }
}

/// Coalesces concurrent/rapid getShareableContent() calls into one fetch.
///
/// Holds the most recent result plus an in-flight fetch task. Callers that
/// arrive while a fetch is already running await that same task rather than
/// starting a second enumeration; only the caller that started the task
/// records the result and clears inFlightTask, so joiners never race each
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

    /// A caller cancelling must not cancel the shared task, other callers
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
/// SCShareableContent is an Objective-C reference type without a Sendable
/// annotation. It is returned as a completed framework snapshot and this
/// wrapper never mutates or exposes any mutable state, so sharing that
/// reference among the capture readers is safe.
private struct ShareableContentSnapshot: @unchecked Sendable {
    let content: SCShareableContent
}

// MARK: - Helper Types

/// SCStream delivers its callbacks on sampleHandlerQueue, a background serial
/// queue, not on any actor. ciContext is an immutable, process-wide
/// CIContext. The only mutable state (latestImage, stopped) is read and
/// written only under lock, which is how the callback safely publishes a
/// frame for the awaiting caller.
final class FrameCaptor: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    /// Shared serial queue for all SCStream sample buffer handlers.
    static let sampleHandlerQueue = DispatchQueue(label: "com.stonerl.Thaw.screencapture")

    /// Process-wide CIContext, shared across every capture, since
    /// FrameCaptor is created per capture.
    ///
    /// Software-rendered: a default context keeps Core Image's Metal kernel
    /// archive (about 5 MB) resident for the life of the process, and the CPU
    /// converts one small strip per frame in well under a millisecond.
    static let sharedCIContext = CIContext(options: [
        .useSoftwareRenderer: true,
        .cacheIntermediates: false,
    ])

    private var ciContext: CIContext {
        FrameCaptor.sharedCIContext
    }

    private let lock = OSAllocatedUnfairLock<(latestImage: CGImage?, stopped: Bool)>(initialState: (nil, false))

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !lock.withLock({ $0.stopped }) else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusInt = attachments.first?[SCStreamFrameInfo.status] as? Int,
              let frameStatus = SCFrameStatus(rawValue: statusInt),
              frameStatus == .complete
        else {
            return
        }

        guard let imageBuffer = sampleBuffer.imageBuffer else {
            return
        }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        storeLatestFrame(cgImage)
    }

    func stream(_: SCStream, didStopWithError _: Error) {
        lock.withLock { $0.stopped = true }
    }

    /// A warm stream may have no new frame when the display is unchanged.
    func latestCompleteFrame() -> (image: CGImage?, stopped: Bool) {
        lock.withLock { ($0.latestImage, $0.stopped) }
    }

    func stopRetainingFrames() {
        lock.withLock {
            $0.stopped = true
            $0.latestImage = nil
        }
    }

    func discardLatestFrame() {
        lock.withLock {
            $0.latestImage = nil
        }
    }

    private func storeLatestFrame(_ image: CGImage) {
        lock.withLock { state in
            guard !state.stopped else { return }
            state.latestImage = image
        }
    }
}
