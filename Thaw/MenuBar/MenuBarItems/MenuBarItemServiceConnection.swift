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

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let diagLog = DiagLog(category: "MenuBarItemService.Connection")
            self.session = Session(queue: queue, diagLog: diagLog)
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
            if let logFile = DiagnosticLogger.shared.currentLogFile {
                let response = await session.sendAsync(request: .configureLogging(filePath: logFile.path))
                if response == nil {
                    diagLog.error("configureLogging request returned nil")
                } else if case .configureLogging = response {
                    // success
                } else {
                    diagLog.error("configureLogging request returned invalid response \(String(describing: response))")
                }
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

        /// Returns the source process identifiers for the given windows in a
        /// single batch XPC request, avoiding concurrent thread explosion
        /// in the XPC service.
        func sourcePIDs(for windows: [WindowInfo]) async -> [pid_t?] {
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

            init(queue: DispatchQueue, diagLog: DiagLog) {
                self.queue = queue
                self.diagLog = diagLog
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
                        guard let self else {
                            return
                        }
                        diagLog.warning("Session was cancelled with error \(error.localizedDescription)")
                        self.invalidate(createdSession.withLock { $0 })
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
                    try newSession.activate()
                    diagLog.debug("getOrCreateSession: XPC session activated successfully")
                    createdSession.withLock { $0 = newSession }
                    session = newSession
                    return newSession
                }
            }

            /// Drops the stored session if it is the one the cancellation
            /// handler fired for; a session created afterwards stays.
            private func invalidate(_ cancelledSession: XPCSession?) {
                guard let cancelledSession else {
                    return
                }
                sessionLock.withLock { session in
                    if session === cancelledSession {
                        session = nil
                    }
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
        init(queue: DispatchQueue, diagLog: DiagLog) {
            self.storage = Storage(queue: queue, diagLog: diagLog)
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
