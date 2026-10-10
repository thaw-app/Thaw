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

        /// What the current helper has been told about diagnostic logging.
        private struct LoggingSyncState {
            /// Only one send at a time, or they can arrive out of order and
            /// leave the helper on a rotated-away file.
            var isSending = false
            /// Set when the session is replaced, since a recycled helper
            /// starts from scratch.
            var isPending = false
            /// Until told about a rotation, the helper writes to a segment
            /// retention will delete.
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

        /// Points the helper at the current log file (or turns file logging
        /// off) and passes the retention policy.
        ///
        /// Re-sent after the session is replaced, or a recycled helper falls
        /// back to OSLog only. Sent even with logging off so the helper
        /// prunes by the app's rules. The file is read at send time, since a
        /// concurrent caller returns early and relies on the running sender.
        func syncLogging() async {
            // One sender at a time, or an older configuration can land last.
            let isSender = loggingSync.withLock { state -> Bool in
                state.isPending = true
                guard !state.isSending else { return false }
                state.isSending = true
                return true
            }
            guard isSender else { return }

            while loggingSync.withLock({ state -> Bool in
                if state.isPending {
                    state.isPending = false
                    return true
                }
                // Release the role in the same critical section, or a caller
                // arriving in between strands its pending flag.
                state.isSending = false
                return false
            }) {
                let logFile = DiagnosticLogger.shared.currentLogFile
                // Before the send, so an invalidation mid-flight isn't
                // overwritten by this send's success.
                loggingSync.withLock { $0.syncedLogFile = logFile }
                guard case .configureLogging = await session.sendAsync(
                    request: .configureLogging(
                        filePath: logFile?.path,
                        rotationPolicy: DiagnosticLogger.shared.rotationPolicy
                    )
                ) else {
                    // Left outstanding; the next batch retries it.
                    diagLog.error("Capture helper rejected logging configuration")
                    loggingSync.withLock { state in
                        state.isPending = true
                        state.isSending = false
                    }
                    return
                }
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
            // Checked here, not on rotation: the helper is launched on
            // demand, and a rotation push would spin one up for nothing.
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

            /// So the log path is re-sent to whatever process comes back.
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

            let diagLog = diagLog
            return await xpcSession.sendCancellable(
                request,
                as: Response.self,
                onDecodeFailure: { error in
                    diagLog.error("Capture XPC reply decode failed: \(error)")
                },
                onSendFailure: { error in
                    diagLog.error("Capture XPC session send failed: \(error)")
                }
            )
        }
    }
}
