//
//  LegacyXPCConnection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os.lock
import XPC

/// An XPC service connection through the C API, for macOS before 26, where XPCSession
/// has no peer requirement. Made on first send and dropped when the service goes away.
final nonisolated class LegacyXPCConnection: @unchecked Sendable {
    private struct Slot {
        var connection: SendableXPCObject?
        var generation: UInt64 = 0
    }

    private let serviceName: String
    private let makeConnection: @Sendable (DispatchQueue) -> xpc_connection_t
    private let queue: DispatchQueue
    private let teamIdentifier: String?
    private let diagLog: DiagLog
    private let onInvalidate: @Sendable () -> Void
    private let slot = OSAllocatedUnfairLock(initialState: Slot())
    /// Makes concurrent first sends share one new connection instead of superseding each other.
    private let creation = NSLock()

    init(
        serviceName: String,
        queue: DispatchQueue,
        teamIdentifier: String?,
        diagLog: DiagLog,
        onInvalidate: @escaping @Sendable () -> Void,
        makeConnection: (@Sendable (DispatchQueue) -> xpc_connection_t)? = nil
    ) {
        self.serviceName = serviceName
        self.makeConnection = makeConnection ?? { queue in xpc_connection_create(serviceName, queue) }
        self.queue = queue
        self.teamIdentifier = teamIdentifier
        self.diagLog = diagLog
        self.onInvalidate = onInvalidate
    }

    deinit {
        cancel()
    }

    /// Sends request and waits for the reply. Nil when the send fails, the
    /// reply carries no payload, or the task is cancelled.
    func send<Response: Decodable & Sendable>(
        _ request: some Encodable,
        as _: Response.Type
    ) async -> Response? {
        let message = xpc_dictionary_create(nil, nil, 0)
        do {
            try LegacyXPCMessage.setPayload(request, in: message)
        } catch {
            diagLog.error("Legacy XPC request encode failed: \(error)")
            return nil
        }
        guard let connection = currentConnection() else { return nil }
        let sendable = SendableXPCObject(object: message)

        typealias Cont = CheckedContinuation<Response?, Never>
        let box = OSAllocatedUnfairLock<Cont?>(initialState: nil)
        let diagLog = diagLog
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: Cont) in
                box.withLock { $0 = continuation }
                if Task.isCancelled {
                    box.withLock { $0.take() }?.resume(returning: nil)
                    return
                }
                xpc_connection_send_message_with_reply(connection.object, sendable.object, queue) { reply in
                    let response: Response? = if let data = LegacyXPCMessage.payload(in: reply) {
                        try? LegacyXPCMessage.decode(Response.self, from: data)
                    } else {
                        nil
                    }
                    if response == nil {
                        diagLog.error("Legacy XPC send failed or returned no usable reply")
                    }
                    box.withLock { $0.take() }?.resume(returning: response)
                }
            }
        } onCancel: {
            box.withLock { $0.take() }?.resume(returning: nil)
        }
    }

    func cancel() {
        let connection = slot.withLock { state -> SendableXPCObject? in
            state.generation += 1
            return state.connection.take()
        }
        guard let connection else { return }
        onInvalidate()
        xpc_connection_cancel(connection.object)
    }

    private func currentConnection() -> SendableXPCObject? {
        creation.lock()
        defer { creation.unlock() }
        if let connection = slot.withLock({ $0.connection }) {
            return connection
        }
        let generation = slot.withLock { state -> UInt64 in
            state.generation += 1
            return state.generation
        }
        let connection = makeConnection(queue)
        guard LegacyXPCMessage.applySameTeamRequirement(to: connection, teamIdentifier: teamIdentifier) else {
            diagLog.error("Legacy XPC connection could not require a same-team peer; not connecting")
            LegacyXPCMessage.discard(connection)
            return nil
        }
        let sendable = SendableXPCObject(object: connection)
        xpc_connection_set_event_handler(connection) { [weak self] event in
            guard let self, xpc_get_type(event) == XPC_TYPE_ERROR else { return }
            diagLog.warning("Legacy XPC connection to \(serviceName) ended: \(Self.describe(event))")
            let invalidated = slot.withLock { state -> Bool in
                guard state.generation == generation, state.connection != nil else { return false }
                state.connection = nil
                return true
            }
            if invalidated {
                // An interrupted connection stays alive until cancelled.
                xpc_connection_cancel(sendable.object)
                onInvalidate()
            }
        }
        // Stored and activated under one lock, so an error event, which runs later on the
        // queue and takes the same lock, always finds the connection it has to clear.
        let stored = slot.withLock { state -> Bool in
            guard state.generation == generation else { return false }
            state.connection = sendable
            xpc_connection_activate(sendable.object)
            return true
        }
        guard stored else {
            LegacyXPCMessage.discard(connection)
            return slot.withLock { $0.connection }
        }
        return sendable
    }

    private static func describe(_ error: xpc_object_t) -> String {
        guard let cString = xpc_dictionary_get_string(error, XPC_ERROR_KEY_DESCRIPTION) else {
            return "unknown error"
        }
        return String(cString: cString)
    }
}
