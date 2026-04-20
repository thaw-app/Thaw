//
//  MenuBarItemServiceConnection.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os.lock

// MARK: - MenuBarItemService.Connection

extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's target queue.
        private let queue: DispatchQueue

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
            self.queue = queue
            self.diagLog = diagLog
        }

        /// Starts the connection.
        func start() async {
            diagLog.debug("Starting MenuBarItemService connection")

            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .start) else {
                    diagLog.error("Start request returned nil")
                    continuation.resume()
                    return
                }
                if case .start = response {
                    continuation.resume()
                } else {
                    diagLog.error("Start request returned invalid response \(String(describing: response))")
                    continuation.resume()
                }
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .sourcePID(window)) else {
                    diagLog.error("Source PID request returned nil")
                    continuation.resume(returning: nil)
                    return
                }
                if case let .sourcePID(pid) = response {
                    continuation.resume(returning: pid)
                } else {
                    diagLog.error("Source PID request returned invalid response \(String(describing: response))")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - MenuBarItemService.Session

extension MenuBarItemService {
    /// A wrapper around an XPC session.
    private final class Session: Sendable {
        /// A session's underlying storage.
        private final class Storage: @unchecked Sendable {
            private let name = MenuBarItemService.name
            private var session: XPCSession?
            private let queue: DispatchQueue
            private let diagLog: DiagLog

            init(queue: DispatchQueue, diagLog: DiagLog) {
                self.queue = queue
                self.diagLog = diagLog
            }

            func getSession() throws -> XPCSession {
                if let session {
                    return session
                }
                diagLog.debug("getOrCreateSession: creating new XPC session for service '\(self.name)'")
                let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                    guard let self else {
                        return
                    }
                    diagLog.warning("Session was cancelled with error \(error.localizedDescription)")
                    self.session = nil
                }
                session.setPeerRequirement(.isFromSameTeam())
                session.setTargetQueue(queue)
                try session.activate()
                diagLog.debug("getOrCreateSession: XPC session activated successfully")
                self.session = session
                return session
            }

            func cancel(reason: String) {
                guard let session = session.take() else {
                    return
                }
                session.cancel(reason: reason)
            }
        }

        /// Protected storage for the underlying XPC session.
        private let storage: OSAllocatedUnfairLock<Storage>

        /// The session's target queue.
        private let queue: DispatchQueue

        /// The session's diagnostic logger.
        private let diagLog: DiagLog

        /// Creates a new session.
        init(queue: DispatchQueue, diagLog: DiagLog) {
            self.storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue, diagLog: diagLog))
            self.queue = queue
            self.diagLog = diagLog
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        /// Sends the given request to the service and returns the response.
        func send(request: Request) -> Response? {
            let session: XPCSession
            do {
                session = try storage.withLock { try $0.getSession() }
            } catch {
                diagLog.error("Failed to get or create XPC session: \(error)")
                return nil
            }

            do {
                let reply = try session.sendSync(request)
                return try reply.decode(as: Response.self)
            } catch {
                diagLog.error("XPC session send failed for request \(String(describing: request)): \(error)")
                return nil
            }
        }
    }
}
