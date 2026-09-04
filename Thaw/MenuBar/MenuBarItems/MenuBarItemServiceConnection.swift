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
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's diagnostic logger.
        private let diagLog: DiagLog

        /// Tracks the one logging configuration the service is allowed to be
        /// missing at a time.
        private struct LoggingSyncState {
            /// Whether a request is on the wire right now. Only one may be:
            /// replies can overtake each other, and the loser would leave the
            /// service pointed at a file the app has already rotated away.
            var isSending = false
            /// Whether the service still owes a configuration. Set when a push
            /// fails, and when the XPC session is dropped — a service that
            /// restarts has no idea which file the app is writing to, and
            /// nothing else would ever tell it.
            var isPending = false
        }

        private let loggingSync: OSAllocatedUnfairLock<LoggingSyncState>

        /// Creates a new connection.
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

        /// Starts the connection.
        func start() async {
            diagLog.debug("Starting MenuBarItemService connection")

            // If the main app already has a diagnostic log file open,
            // hand its path to the XPC service so both processes append
            // to the same file. Sent before the start request so the
            // XPC service is logging to disk by the time it handles any
            // subsequent traffic. When file logging is off in the main
            // app currentLogFile is nil and the XPC service simply logs
            // to OSLog only, matching the prior release-build behaviour.
            //
            // Sent unconditionally: even with logging off, this hands over the
            // retention policy the service prunes the shared directory by.
            // Only the initial push runs on the launch path: AppState.setupTask
            // awaits start() before the rest of its setup, so the retry loop's
            // 2s sleeps must not sit in between. A failing push marks the work
            // pending and retries off the launch path.
            //
            // Cleared before the send, the way `syncLogging()` does it, and
            // never after: the session can be dropped while the request is in
            // flight, and the invalidation that marks the configuration
            // outstanding again must not be undone by this send's success.
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
        /// Called at startup, on every log rotation, and when the user changes
        /// a diagnostics setting. The state is read here, at send time, rather
        /// than captured by the caller: a notification that was queued before a
        /// rotation would otherwise point the service at the file that rotation
        /// has already replaced.
        func syncLogging() async {
            // One sender at a time. A second caller only marks the work as
            // outstanding: the sender already running will pick it up, and the
            // state it reads then is newer than anything this caller could
            // pass along.
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
                // No outstanding work: release the sender role in the same
                // critical section that observed the empty flag. Clearing it
                // later (after the lock was released) raced a caller that
                // arrived in between — it saw isSending set, declined to
                // send, and the pending flag it had just set was stranded
                // with no sender left to service it.
                state.isSending = false
                return false
            }) {
                if await sendLoggingConfiguration() {
                    attemptsLeft = Self.loggingSyncAttempts
                    continue
                }

                // Put the work back and try again shortly. Leaving it to the
                // next request would be enough on a busy app, but a quiet one
                // could sit for minutes with the service writing to a file this
                // process has already rotated away.
                loggingSync.withLock { $0.isPending = true }
                attemptsLeft -= 1
                guard attemptsLeft > 0 else {
                    // Exhausted: the pending flag stays set for the next
                    // trigger; release the sender role explicitly, since the
                    // loop exit above is what normally clears it.
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

        /// Returns the source process identifiers for the given windows in a
        /// single batch XPC request, avoiding concurrent thread explosion
        /// in the XPC service.
        func sourcePIDs(for windows: [WindowInfo]) async -> [pid_t?] {
            // The app's most frequent request, and so the cheapest place to
            // notice that the service is owed a logging configuration. Not
            // awaited: a sync stuck in its retry cycle sleeps for seconds and
            // must not delay the request — the kicked-off task re-enters
            // syncLogging, whose single-sender lock makes extra kickoffs
            // no-ops.
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
        /// A session's underlying storage.
        ///
        /// Self-locking: every access to the stored session, including the
        /// invalidation fired by the XPC cancellation handler on an
        /// arbitrary thread, goes through `sessionLock`. The cancellation
        /// handler previously wrote `session = nil` outside the lock that
        /// guarded every other access, racing `getSession`, and a stale
        /// handler could nil out a newer session created after the one it
        /// belonged to.
        private final nonisolated class Storage: @unchecked Sendable {
            private let name = MenuBarItemService.name
            private let sessionLock = OSAllocatedUnfairLock<XPCSession?>(initialState: nil)
            private let queue: DispatchQueue
            private let diagLog: DiagLog

            /// Called when a session is dropped, so state the peer only learns
            /// by being told — the diagnostic log path — can be sent again to
            /// whatever process comes back.
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
                    // Box so the cancellation handler can identify the session
                    // it belongs to: the handler is passed to the initializer,
                    // before the created instance exists to capture.
                    let createdSession = OSAllocatedUnfairLock<XPCSession?>(initialState: nil)
                    let newSession = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                        self?.handleCancellation(error, of: createdSession)
                    }
                    // Same-team peer validation can never pass in a build signed
                    // without a team identifier (ad-hoc/personal builds) — every
                    // send would fail with "Peer forbidden (code signing)".
                    // Mirrors the teamless fallback in the service's Listener.
                    if CodeSigningInfo.processTeamIdentifier != nil {
                        newSession.setPeerRequirement(.isFromSameTeam())
                    } else {
                        diagLog.notice("getOrCreateSession: no team identifier (ad-hoc build), skipping peer requirement")
                    }
                    newSession.setTargetQueue(queue)
                    // Populated before activate(): a session cancelled right
                    // after activation would otherwise race the box write,
                    // find it empty, and leave the dead session stored. If
                    // activate() throws, the handler firing against the
                    // populated box is a no-op — nothing was stored to drop.
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

        /// The session's diagnostic logger.
        private let diagLog: DiagLog

        /// Creates a new session.
        init(queue: DispatchQueue, diagLog: DiagLog, onInvalidate: @escaping @Sendable () -> Void) {
            self.storage = Storage(queue: queue, diagLog: diagLog, onInvalidate: onInvalidate)
            self.diagLog = diagLog
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.cancel(reason: reason)
        }

        /// Sends the given request to the service asynchronously and returns the response.
        ///
        /// Uses the non-blocking `XPCSession.send(_:replyHandler:)` API so that Swift
        /// cooperative-thread-pool threads are never stranded on a blocking C call.
        /// The continuation is protected by a shared `OSAllocatedUnfairLock`-guarded
        /// box so that exactly one of (reply handler) or (cancellation handler) resumes
        /// it. This lets upstream `Task` cancellation (e.g. from `Task.withTimeout`)
        /// unblock the caller immediately without stranding a thread.
        func sendAsync(request: Request) async -> Response? {
            let xpcSession: XPCSession
            do {
                xpcSession = try storage.getSession()
            } catch {
                diagLog.error("Failed to get or create XPC session: \(error)")
                return nil
            }

            // Shared mutable box: holds the continuation until one of the two
            // racing paths (reply handler vs. cancellation handler) claims it.
            // Setting the stored value to nil is the "claim" — whichever path
            // wins claims it and resumes; the other path sees nil and does nothing.
            typealias Cont = CheckedContinuation<Response?, Never>
            let box = OSAllocatedUnfairLock<Cont?>(initialState: nil)

            return await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: Cont) in
                    performXPCSend(xpcSession, request: request, box: box, continuation: continuation)
                }
            } onCancel: {
                // Fired on an arbitrary thread when the enclosing Task is cancelled.
                // Claim the continuation and resume it immediately so the caller is
                // unblocked. The XPC reply handler will see the box is empty and no-op.
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
            // Store the continuation so the cancellation handler can reach it.
            box.withLock { $0 = continuation }

            // Fast path: task was cancelled after we stored the continuation.
            // The onCancel handler may have already claimed it, so try to claim
            // here; if we succeed, resume immediately to avoid starting the XPC send.
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
                            let decoded = try message.decode(as: Response.self)
                            cont.resume(returning: decoded)
                        } catch {
                            self.diagLog.error(
                                "XPC reply decode failed for request \(String(describing: request)): \(error)"
                            )
                            cont.resume(returning: nil)
                        }
                    case let .failure(error):
                        self.diagLog.error(
                            "XPC session send failed for request \(String(describing: request)): \(error)"
                        )
                        cont.resume(returning: nil)
                    }
                }
            } catch {
                diagLog.error(
                    "XPC session send failed for request \(String(describing: request)): \(error)"
                )
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
