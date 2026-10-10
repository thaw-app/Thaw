//
//  DisplayStripCaptureSession.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import ScreenCaptureKit

/// Keeps the system recording session stable while the layout view refreshes.
/// An idle lease ends capture when no consumer has requested another frame.
actor DisplayStripCaptureSession {
    static let shared = DisplayStripCaptureSession()
    static let idleTimeout: Duration = .seconds(8)

    struct Key: Equatable, Sendable {
        let displayID: CGDirectDisplayID
        let displayFrame: CGRect
        let stripFrame: CGRect
        let scale: CGFloat
        let excludedWindowIDs: [CGWindowID]
    }

    /// Bookkeeping stays on this actor; capture tasks share only immutable stream/captor references with locked frame state.
    private final class Session: @unchecked Sendable {
        let visibilityGeneration: UInt64
        var key: Key
        var version = StripSessionVersion()
        let stream: SCStream
        let captor: FrameCaptor
        var started: Task<Void, Error>
        var idleTask: Task<Void, Never>?

        init(key: Key, visibilityGeneration: UInt64, filter: SCContentFilter, configuration: SCStreamConfiguration) throws {
            self.key = key
            self.visibilityGeneration = visibilityGeneration
            let captor = FrameCaptor()
            self.captor = captor
            let stream = SCStream(filter: filter, configuration: configuration, delegate: captor)
            self.stream = stream
            try stream.addStreamOutput(captor, type: .screen, sampleHandlerQueue: FrameCaptor.sampleHandlerQueue)
            nonisolated(unsafe) let captureStream = stream
            started = Task {
                guard ScreenCapture.isCaptureUITicketCurrent(visibilityGeneration) else { throw CancellationError() }
                try await captureStream.startCapture()
                if !ScreenCapture.isCaptureUITicketCurrent(visibilityGeneration) {
                    try? await captureStream.stopCapture()
                    throw CancellationError()
                }
            }
        }
    }

    private var sessions: [CGDirectDisplayID: Session] = [:]

    func capture(key: Key, visibilityGeneration: UInt64, filter: sending SCContentFilter, configuration: sending SCStreamConfiguration) async throws -> CGImage {
        guard ScreenCapture.isCaptureUITicketCurrent(visibilityGeneration) else { throw CancellationError() }
        let session: Session
        if let existing = sessions[key.displayID], existing.visibilityGeneration == visibilityGeneration, !existing.captor.latestCompleteFrame().stopped {
            session = existing
            if existing.key != key {
                let previousUpdate = existing.started
                nonisolated(unsafe) let updatedFilter = filter
                nonisolated(unsafe) let updatedConfiguration = configuration
                existing.started = Task {
                    try await previousUpdate.value
                    try await existing.stream.updateContentFilter(updatedFilter)
                    try await existing.stream.updateConfiguration(updatedConfiguration)
                    existing.captor.discardLatestFrame()
                }
                existing.key = key
                existing.version.reconfigure()
                ScreenCapture.diagLog.info("StripSession: update display=\(key.displayID) exclusions=\(key.excludedWindowIDs.count)")
            } else {
                ScreenCapture.diagLog.debug("StripSession: reuse display=\(key.displayID)")
            }
        } else {
            if let existing = sessions[key.displayID] {
                retire(existing, reason: "stream stopped")
            }
            session = try Session(key: key, visibilityGeneration: visibilityGeneration, filter: filter, configuration: configuration)
            sessions[key.displayID] = session
            ScreenCapture.diagLog.info("StripSession: start display=\(key.displayID) exclusions=\(key.excludedWindowIDs.count)")
        }
        renewLease(session)
        let revision = session.version.configuration
        let ready = session.started
        let deadline = ContinuousClock.now.advanced(by: ScreenCapture.screenshotTimeout)
        do {
            try await withAbandoningTimeout(ScreenCapture.screenshotTimeout) {
                try await ready.value
            }
            while true {
                try Task.checkCancellation()
                guard ScreenCapture.isCaptureUITicketCurrent(visibilityGeneration), sessions[key.displayID] === session, session.version.matchesConfiguration(revision) else { throw CancellationError() }
                let snapshot = session.captor.latestCompleteFrame()
                guard !snapshot.stopped else { throw CaptureStopped() }
                if snapshot.image != nil {
                    break
                }
                guard ContinuousClock.now < deadline else { throw TaskTimeoutError() }
                try await Task.sleep(for: .milliseconds(16))
            }
            // Settle after the first complete frame, even for slow initial delivery or warm requests.
            try await Task.sleep(for: ScreenCapture.stripSettleWindow)
            try Task.checkCancellation()
            guard ScreenCapture.isCaptureUITicketCurrent(visibilityGeneration), sessions[key.displayID] === session, session.version.matchesConfiguration(revision) else { throw CancellationError() }
            let snapshot = session.captor.latestCompleteFrame()
            guard !snapshot.stopped, let image = snapshot.image else { throw CaptureStopped() }
            renewLease(session)
            return image
        } catch is CancellationError {
            // Cancellation leaves the session for other consumers; its idle lease retires it if none remain.
            throw CancellationError()
        } catch {
            if sessions[key.displayID] === session, session.version.matchesConfiguration(revision) {
                retire(session, reason: "capture failed")
            }
            throw error
        }
    }

    func retireBeforeVisibilityGeneration(_ generation: UInt64) {
        for session in Array(sessions.values) where session.visibilityGeneration < generation {
            retire(session, reason: "last UI closed")
        }
    }

    private func renewLease(_ session: Session) {
        session.idleTask?.cancel()
        let lease = session.version.renewLease()
        session.idleTask = Task { [weak self, weak session] in
            do { try await Task.sleep(for: Self.idleTimeout) } catch { return }
            guard let self, let session else { return }
            await self.expire(session, lease: lease)
        }
    }

    private func expire(_ session: Session, lease: UInt64) {
        guard sessions[session.key.displayID] === session, session.version.matchesLease(lease) else { return }
        retire(session, reason: "idle")
    }

    private func retire(_ session: Session, reason: String) {
        sessions[session.key.displayID] = nil
        session.idleTask?.cancel()
        session.idleTask = nil
        session.captor.stopRetainingFrames()
        ScreenCapture.diagLog.info("StripSession: stop display=\(session.key.displayID) reason=\(reason)")
        let ready = session.started
        Task { try? await session.stream.stopCapture() }
        Task {
            // Stop again after a late startCapture completes so a timed-out start cannot leave a live orphan.
            try? await ready.value
            try? await session.stream.stopCapture()
        }
    }

    private struct CaptureStopped: Error {}
}

/// Tickets detect stale work across suspension, including repeated configurations and idle timers queued before lease renewal.
struct StripSessionVersion {
    private(set) var configuration: UInt64 = 0
    private var lease: UInt64 = 0

    mutating func reconfigure() {
        configuration &+= 1
    }

    mutating func renewLease() -> UInt64 {
        lease &+= 1
        return lease
    }

    func matchesConfiguration(_ ticket: UInt64) -> Bool {
        configuration == ticket
    }

    func matchesLease(_ ticket: UInt64) -> Bool {
        lease == ticket
    }
}
