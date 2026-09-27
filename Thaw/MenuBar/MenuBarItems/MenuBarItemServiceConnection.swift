//
//  MenuBarItemServiceConnection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os.lock
import XPC

// MARK: - MenuBarItemService.Connection

extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        static let shared = Connection()

        private let session: Session

        private let diagLog: DiagLog

        /// Tracks the one logging configuration the service is allowed to be
        /// missing at a time.
        private struct LoggingSyncState {
            /// Only one request may be in flight: replies can overtake each
            /// other and leave the service on a rotated-away file.
            var isSending = false
            /// Set when a push fails or the session drops, since a restarted
            /// service doesn't know which file the app is writing to.
            var isPending = false
        }

        private let loggingSync: OSAllocatedUnfairLock<LoggingSyncState>

        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let diagLog = DiagLog(category: "MenuBarItemService.Connection")
            let loggingSync = OSAllocatedUnfairLock(initialState: LoggingSyncState())
            self.loggingSync = loggingSync
            self.session = Session(queue: queue, diagLog: diagLog) {
                loggingSync.withLock { $0.isPending = true }
            }
            self.diagLog = diagLog
        }

        func start() async {
            diagLog.debug("Starting MenuBarItemService connection")

            // Send the log file and retention policy before the start request,
            // even with logging off. Only one push on the launch path, since
            // AppState.setupTask awaits start(); a failure retries later.
            //
            // Cleared before the send, never after, so an invalidation during
            // the send can't be undone by its success.
            loggingSync.withLock { $0.isPending = false }
            let accepted = await sendLoggingConfiguration()
            if !accepted || loggingSync.withLock({ $0.isPending }) {
                Task { await syncLogging() }
            }

            let response = await session.sendAsync(request: .start)
            guard let response else {
                diagLog.error("Start request returned nil")
                return
            }
            if case .start = response {
                // success
            } else {
                diagLog.error("Start request returned invalid response \(String(describing: response))")
            }
        }

        /// Points the service at the diagnostic log file the app is writing to
        /// right now, or turns its file logging off when there is none, and
        /// hands over the retention policy along with it.
        ///
        /// State is read at send time, so a notification queued before a
        /// rotation can't point the service at the replaced file.
        func syncLogging() async {
            // One sender at a time; other callers only mark work pending.
            let isSender = loggingSync.withLock { state -> Bool in
                state.isPending = true
                guard !state.isSending else { return false }
                state.isSending = true
                return true
            }
            guard isSender else { return }

            var attemptsLeft = Self.loggingSyncAttempts
            while loggingSync.withLock({ state -> Bool in
                if state.isPending {
                    state.isPending = false
                    return true
                }
                // Release the sender role in the same critical section that
                // saw no pending work, or a caller arriving between could
                // strand its pending flag.
                state.isSending = false
                return false
            }) {
                if await sendLoggingConfiguration() {
                    attemptsLeft = Self.loggingSyncAttempts
                    continue
                }

                // Retry soon: a quiet app could leave the service writing to a
                // rotated-away file for minutes.
                loggingSync.withLock { $0.isPending = true }
                attemptsLeft -= 1
                guard attemptsLeft > 0 else {
                    // Leave the pending flag for the next trigger.
                    loggingSync.withLock { $0.isSending = false }
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }

        /// How many times a failing configuration push is retried before it is
        /// left for the next request to carry.
        private static let loggingSyncAttempts = 3

        /// Sends the current logging configuration once.
        ///
        /// - Returns: Whether the service accepted it.
        private func sendLoggingConfiguration() async -> Bool {
            let request = MenuBarItemService.Request.configureLogging(
                filePath: DiagnosticLogger.shared.currentLogFile?.path,
                rotationPolicy: DiagnosticLogger.shared.rotationPolicy
            )
            let response = await session.sendAsync(request: request)
            guard case .configureLogging = response else {
                diagLog.error("configureLogging request returned \(String(describing: response))")
                return false
            }
            return true
        }

        /// One batch request, avoiding a thread explosion in the XPC service.
        func sourcePIDs(for windows: [WindowInfo]) async -> [pid_t?] {
            // The most frequent request, so a cheap place to catch a pending
            // logging sync. Not awaited: its retries sleep for seconds.
            if loggingSync.withLock({ $0.isPending }) {
                Task { await syncLogging() }
            }
            let response = await session.sendAsync(request: .sourcePIDs(windows))
            guard let response else {
                diagLog.error("Source PIDs batch request returned nil")
                return Array(repeating: nil, count: windows.count)
            }
            if case let .sourcePIDs(pids) = response {
                return pids
            } else {
                diagLog.error("Source PIDs batch request returned invalid response \(String(describing: response))")
                return Array(repeating: nil, count: windows.count)
            }
        }
    }
}

// MARK: - MenuBarItemService.Session

extension MenuBarItemService {
    /// A wrapper around an XPC session.
    private final nonisolated class Session: Sendable {
        /// Every access goes through `sessionLock`, including the cancellation
        /// handler, so a stale handler can't nil out a newer session.
        private final nonisolated class Storage: @unchecked Sendable {
            private let name = MenuBarItemService.name
            private let sessionLock = OSAllocatedUnfairLock<XPCSession?>(initialState: nil)
            private let queue: DispatchQueue
            private let diagLog: DiagLog

            /// Called when a session drops, so the log path can be resent.
            private let onInvalidate: @Sendable () -> Void

            init(queue: DispatchQueue, diagLog: DiagLog, onInvalidate: @escaping @Sendable () -> Void) {
                self.queue = queue
                self.diagLog = diagLog
                self.onInvalidate = onInvalidate
            }

            func getSession() throws -> XPCSession {
                try sessionLock.withLock { session in
                    if let session {
                        return session
                    }
                    diagLog.debug("getOrCreateSession: creating new XPC session for service '\(self.name)'")
                    // The handler is passed before the session exists, so it
                    // finds its session through this box.
                    let createdSession = OSAllocatedUnfairLock<XPCSession?>(initialState: nil)
                    let newSession = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                        self?.handleCancellation(error, of: createdSession)
                    }
                    // Same-team validation always fails in ad-hoc builds
                    // ("Peer forbidden"). Mirrors the service's Listener.
                    if CodeSigningInfo.processTeamIdentifier != nil {
                        newSession.setPeerRequirement(.isFromSameTeam())
                    } else {
                        diagLog.notice("getOrCreateSession: no team identifier (ad-hoc build), skipping peer requirement")
                    }
                    newSession.setTargetQueue(queue)
                    // Populated before activate(), or a quick cancellation
                    // would find it empty and leave the dead session stored.
                    createdSession.withLock { $0 = newSession }
                    try newSession.activate()
                    diagLog.debug("getOrCreateSession: XPC session activated successfully")
                    session = newSession
                    return newSession
                }
            }

            /// Handles the XPC cancellation callback for the session stored
            /// in `sessionBox`. Arrives on an arbitrary thread.
            private func handleCancellation(
                _ error: XPCRichError,
                of sessionBox: OSAllocatedUnfairLock<XPCSession?>
            ) {
                diagLog.warning("Session was cancelled with error \(error.localizedDescription)")
                invalidate(sessionBox.withLock { $0 })
            }

            /// Drops the stored session if it is the one the cancellation
            /// handler fired for; a session created afterwards stays.
            private func invalidate(_ cancelledSession: XPCSession?) {
                guard let cancelledSession else {
                    return
                }
                let dropped = sessionLock.withLock { session -> Bool in
                    guard session === cancelledSession else { return false }
                    session = nil
                    return true
                }
                if dropped {
                    onInvalidate()
                }
            }

            func cancel(reason: String) {
                guard let session = sessionLock.withLock({ $0.take() }) else {
                    return
                }
                session.cancel(reason: reason)
            }
        }

        /// The underlying XPC session storage, which synchronizes internally.
        private let storage: Storage

        private let diagLog: DiagLog

        init(queue: DispatchQueue, diagLog: DiagLog, onInvalidate: @escaping @Sendable () -> Void) {
            self.storage = Storage(queue: queue, diagLog: diagLog, onInvalidate: onInvalidate)
            self.diagLog = diagLog
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        func cancel(reason: String) {
            storage.cancel(reason: reason)
        }

        /// Sends the given request to the service asynchronously and returns the response.
        ///
        /// Non-blocking, so cooperative threads are never stranded. Exactly one
        /// of the reply or cancellation handler resumes the continuation, so
        /// Task cancellation unblocks the caller immediately.
        func sendAsync(request: Request) async -> Response? {
            let xpcSession: XPCSession
            do {
                xpcSession = try storage.getSession()
            } catch {
                diagLog.error("Failed to get or create XPC session: \(error)")
                return nil
            }

            let diagLog = diagLog
            return await xpcSession.sendCancellable(
                request,
                as: Response.self,
                onDecodeFailure: { error in
                    diagLog.error(
                        "XPC reply decode failed for request \(String(describing: request)): \(error)"
                    )
                },
                onSendFailure: { error in
                    diagLog.error(
                        "XPC session send failed for request \(String(describing: request)): \(error)"
                    )
                }
            )
        }
    }
}
