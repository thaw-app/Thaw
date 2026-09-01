//
//  MenuBarCaptureServiceConnection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import os.lock
import XPC

extension MenuBarCaptureService {
    /// A connection to the `MenuBarCaptureService` XPC service.
    final class Connection: Sendable {
        static let shared = Connection()

        private let session: Session
        private let queue: DispatchQueue
        private let diagLog: DiagLog
        private let requestIDs = OSAllocatedUnfairLock(initialState: UInt64(0))

        /// Tracks what the current helper process has been told about
        /// diagnostic logging.
        private struct LoggingSyncState {
            /// Whether the helper has never been told which log file to write
            /// to. Set when the session is replaced — a recycled or relaunched
            /// helper starts from scratch — and cleared by the next successful
            /// logging push.
            var isPending = false
            /// The file the helper was last pointed at. A rotation mints a new
            /// one, and until the helper is told, it keeps its descriptor on a
            /// segment retention eventually deletes out from under it.
            var syncedLogFile: URL?
        }

        private let loggingSync: OSAllocatedUnfairLock<LoggingSyncState>

        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarCaptureService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let diagLog = DiagLog(category: "MenuBarCaptureService.Connection")
            let loggingSync = OSAllocatedUnfairLock(initialState: LoggingSyncState())
            self.loggingSync = loggingSync
            self.session = Session(queue: queue, diagLog: diagLog) {
                loggingSync.withLock { $0.isPending = true }
            }
            self.queue = queue
            self.diagLog = diagLog
        }

        func start() async {
            await syncLogging()
            _ = await session.sendAsync(request: .start)
        }

        /// Points the helper at the diagnostic log file the app is writing to
        /// right now, or turns its file logging off when there is none, and
        /// hands over the retention policy along with it.
        ///
        /// Re-sent whenever the session is replaced: a recycled helper is a
        /// fresh process that has never been told which file to log to, and
        /// without this push it silently falls back to OSLog-only logging.
        /// Sent even with logging off, so the helper still prunes the shared
        /// directory by the app's rules rather than by its own defaults.
        func syncLogging() async {
            let logFile = DiagnosticLogger.shared.currentLogFile
            // Recorded before the send rather than after it: the session can be
            // dropped while the request is in flight, and the invalidation that
            // marks the configuration outstanding again must survive this
            // send's success.
            loggingSync.withLock { state in
                state.isPending = false
                state.syncedLogFile = logFile
            }
            guard case .configureLogging = await session.sendAsync(
                request: .configureLogging(
                    filePath: logFile?.path,
                    rotationPolicy: DiagnosticLogger.shared.rotationPolicy
                )
            ) else {
                // Left outstanding on purpose: the next batch retries it.
                diagLog.error("Capture helper rejected logging configuration")
                loggingSync.withLock { $0.isPending = true }
                return
            }
        }

        func recycle() async {
            _ = await session.sendAsync(request: .recycle)
            session.cancel(reason: "recycle")
        }

        func capture(
            windowIDs: [CGWindowID],
            scale: CGFloat,
            option: CGWindowImageOption
        ) async -> [Frame] {
            // The cheapest place to notice that the helper is out of date:
            // either the session was replaced since the last batch, so the
            // helper handling it has never been told which file to log to, or
            // the app has rotated to a file the helper knows nothing about.
            // Checked here rather than driven from `DiagnosticLogger.onRotate`
            // because the helper is launched on demand and recycled
            // constantly, and a rotation push would spin one up only to hand
            // it a file it may never write to.
            let logFile = DiagnosticLogger.shared.currentLogFile
            if loggingSync.withLock({ $0.isPending || $0.syncedLogFile != logFile }) {
                await syncLogging()
            }
            if let frames = await sendCapture(
                windowIDs: windowIDs,
                scale: scale,
                option: option
            ) {
                return frames
            }
            session.cancel(reason: "retry after interruption")
            return await sendCapture(
                windowIDs: windowIDs,
                scale: scale,
                option: option
            ) ?? []
        }

        private func nextRequestID() -> UInt64 {
            requestIDs.withLock { value in
                value += 1
                return value
            }
        }

        private func sendCapture(
            windowIDs: [CGWindowID],
            scale: CGFloat,
            option: CGWindowImageOption
        ) async -> [Frame]? {
            let requestID = nextRequestID()
            let request = Request.captureBatch(
                CaptureBatchRequest(
                    requestID: requestID,
                    windowIDs: windowIDs,
                    optionRawValue: option.rawValue,
                    expectedScale: Double(scale)
                )
            )
            guard let response = await session.sendAsync(request: request) else {
                return nil
            }
            guard let batch = acceptedResponse(requestID: requestID, response: response) else {
                diagLog.error("Capture request \(requestID) got a stale or invalid response")
                return []
            }
            return batch.frames.filter { frame in
                isValidBGRAFrame(
                    width: frame.width,
                    height: frame.height,
                    bytesPerRow: frame.bytesPerRow,
                    pixelCount: frame.pixels.count
                ) && frame.scale > 0 && frame.scale.isFinite
            }
        }
    }
}

extension MenuBarCaptureService {
    private final nonisolated class Session: Sendable {
        private final nonisolated class Storage: @unchecked Sendable {
            private struct Slot {
                var session: XPCSession?
                var generation: UInt64 = 0
            }

            private let name = MenuBarCaptureService.name
            private let slot = OSAllocatedUnfairLock(initialState: Slot())
            private let queue: DispatchQueue
            private let diagLog: DiagLog

            /// Called when a session is dropped, so state the peer only
            /// learns by being told — the diagnostic log path — can be sent
            /// again to whatever process comes back.
            private let onInvalidate: @Sendable () -> Void

            init(
                queue: DispatchQueue,
                diagLog: DiagLog,
                onInvalidate: @escaping @Sendable () -> Void
            ) {
                self.queue = queue
                self.diagLog = diagLog
                self.onInvalidate = onInvalidate
            }

            func getSession() throws -> XPCSession {
                if let session = slot.withLock({ $0.session }) {
                    return session
                }
                let generation = slot.withLock { state -> UInt64 in
                    state.generation += 1
                    return state.generation
                }
                let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                    guard let self else { return }
                    self.diagLog.warning(
                        "Capture session was cancelled with error \(error.localizedDescription)"
                    )
                    let invalidated = self.slot.withLock { state -> Bool in
                        guard state.generation == generation, state.session != nil else { return false }
                        state.session = nil
                        return true
                    }
                    if invalidated {
                        self.onInvalidate()
                    }
                }
                if CodeSigningInfo.processTeamIdentifier != nil {
                    session.setPeerRequirement(.isFromSameTeam())
                }
                session.setTargetQueue(queue)
                try session.activate()
                let superseded = slot.withLock { state -> Bool in
                    guard state.generation == generation else { return true }
                    state.session = session
                    return false
                }
                if superseded {
                    session.cancel(reason: "superseded")
                }
                return session
            }

            func cancel(reason: String) {
                let session = slot.withLock { state -> XPCSession? in
                    state.generation += 1
                    return state.session.take()
                }
                guard let session else { return }
                onInvalidate()
                session.cancel(reason: reason)
            }
        }

        private let storage: OSAllocatedUnfairLock<Storage>
        private let diagLog: DiagLog

        init(
            queue: DispatchQueue,
            diagLog: DiagLog,
            onInvalidate: @escaping @Sendable () -> Void
        ) {
            self.storage = OSAllocatedUnfairLock(
                initialState: Storage(queue: queue, diagLog: diagLog, onInvalidate: onInvalidate)
            )
            self.diagLog = diagLog
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        func sendAsync(request: Request) async -> Response? {
            let xpcSession: XPCSession
            do {
                xpcSession = try storage.withLock { try $0.getSession() }
            } catch {
                diagLog.error("Failed to get or create capture XPC session: \(error)")
                return nil
            }

            typealias Cont = CheckedContinuation<Response?, Never>
            let box = OSAllocatedUnfairLock<Cont?>(initialState: nil)

            return await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: Cont) in
                    performXPCSend(xpcSession, request: request, box: box, continuation: continuation)
                }
            } onCancel: {
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
            }
        }

        private func performXPCSend(
            _ xpcSession: XPCSession,
            request: Request,
            box: OSAllocatedUnfairLock<CheckedContinuation<Response?, Never>?>,
            continuation: CheckedContinuation<Response?, Never>
        ) {
            box.withLock { $0 = continuation }
            if Task.isCancelled {
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
                return
            }

            do {
                try xpcSession.send(request) { (result: Result<XPCReceivedMessage, XPCRichError>) in
                    guard let cont = box.withLock({ $0.take() }) else { return }
                    switch result {
                    case let .success(message):
                        do {
                            cont.resume(returning: try message.decode(as: Response.self))
                        } catch {
                            self.diagLog.error("Capture XPC reply decode failed: \(error)")
                            cont.resume(returning: nil)
                        }
                    case let .failure(error):
                        self.diagLog.error("Capture XPC session send failed: \(error)")
                        cont.resume(returning: nil)
                    }
                }
            } catch {
                diagLog.error("Capture XPC session send failed: \(error)")
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
