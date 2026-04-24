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

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            let response = await session.sendAsync(request: .sourcePID(window))
            guard let response else {
                diagLog.error("Source PID request returned nil")
                return nil
            }
            if case let .sourcePID(pid) = response {
                return pid
            } else {
                diagLog.error("Source PID request returned invalid response \(String(describing: response))")
                return nil
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
                xpcSession = try storage.withLock { try $0.getSession() }
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
                    // Store the continuation so the cancellation handler can reach it.
                    box.withLock { $0 = continuation }

                    // Fast path: task was cancelled before we stored the continuation,
                    // so the onCancel handler already fired and saw nil. Claim & resume.
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
            } onCancel: {
                // Fired on an arbitrary thread when the enclosing Task is cancelled.
                // Claim the continuation and resume it immediately so the caller is
                // unblocked. The XPC reply handler will see the box is empty and no-op.
                if let cont = box.withLock({ $0.take() }) {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
