//
//  LegacyXPCConnectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import os.lock
import Testing
@testable import Thaw
import XPC

@Suite("Legacy XPC connection")
struct LegacyXPCConnectionTests {
    /// An anonymous in-process listener that answers every request with response,
    /// or with an empty reply when response is nil.
    private final class EchoListener: @unchecked Sendable {
        let listener: xpc_connection_t
        let endpoint: SendableXPCObject

        private let peers = OSAllocatedUnfairLock(initialState: [SendableXPCObject]())

        init(queue: DispatchQueue, response: MenuBarCaptureService.Response?) {
            listener = xpc_connection_create(nil, queue)
            let peers = peers
            xpc_connection_set_event_handler(listener) { peer in
                guard xpc_get_type(peer) == XPC_TYPE_CONNECTION else { return }
                let sendablePeer = SendableXPCObject(object: peer)
                peers.withLock { $0.append(sendablePeer) }
                xpc_connection_set_event_handler(peer) { message in
                    guard xpc_get_type(message) == XPC_TYPE_DICTIONARY, let reply = xpc_dictionary_create_reply(message)
                    else { return }
                    if let response {
                        try? LegacyXPCMessage.setPayload(response, in: reply)
                    }
                    xpc_connection_send_message(sendablePeer.object, reply)
                }
                xpc_connection_activate(peer)
            }
            xpc_connection_activate(listener)
            endpoint = SendableXPCObject(object: xpc_endpoint_create(listener))
        }

        deinit {
            for peer in peers.withLock({ $0 }) {
                xpc_connection_cancel(peer.object)
            }
            xpc_connection_cancel(listener)
        }
    }

    private static func makeConnection(
        to echo: EchoListener,
        queue: DispatchQueue,
        onInvalidate: @escaping @Sendable () -> Void = {}
    ) -> LegacyXPCConnection {
        let endpoint = echo.endpoint
        return LegacyXPCConnection(
            serviceName: "test",
            queue: queue,
            teamIdentifier: nil,
            diagLog: DiagLog(category: "LegacyXPCConnectionTests"),
            onInvalidate: onInvalidate,
            makeConnection: { queue in
                let connection = xpc_connection_create_from_endpoint(endpoint.object)
                xpc_connection_set_target_queue(connection, queue)
                return connection
            }
        )
    }

    @Test("A request gets the service's response back")
    func roundTrip() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.roundTrip")
        let echo = EchoListener(queue: queue, response: .start)
        let connection = Self.makeConnection(to: echo, queue: queue)
        defer { connection.cancel() }

        let response = await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self)

        #expect(response == .start)
    }

    @Test("An empty reply comes back as nil")
    func emptyReply() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.emptyReply")
        let echo = EchoListener(queue: queue, response: nil)
        let connection = Self.makeConnection(to: echo, queue: queue)
        defer { connection.cancel() }

        let response = await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self)

        #expect(response == nil)
    }

    @Test("Cancelling a live connection reports the invalidation")
    func cancelReportsInvalidation() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.cancel")
        let echo = EchoListener(queue: queue, response: .start)
        let invalidations = OSAllocatedUnfairLock(initialState: 0)
        let connection = Self.makeConnection(to: echo, queue: queue) {
            invalidations.withLock { $0 += 1 }
        }

        _ = await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self)
        connection.cancel()
        connection.cancel()

        #expect(invalidations.withLock { $0 } == 1)
    }

    @Test("A cancelled task gets nil without waiting for the reply")
    func cancelledTask() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.cancelledTask")
        let echo = EchoListener(queue: queue, response: .start)
        let connection = Self.makeConnection(to: echo, queue: queue)
        defer { connection.cancel() }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self)
        }

        #expect(await task.value == nil)
    }

    private struct Unencodable: Encodable {
        func encode(to _: Encoder) throws {
            throw EncodingError.invalidValue(0, .init(codingPath: [], debugDescription: "test"))
        }
    }

    @Test("A request that can't be encoded isn't sent")
    func unencodableRequest() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.unencodable")
        let echo = EchoListener(queue: queue, response: .start)
        let connection = Self.makeConnection(to: echo, queue: queue)
        defer { connection.cancel() }

        #expect(await connection.send(Unencodable(), as: MenuBarCaptureService.Response.self) == nil)
    }

    @Test("A connection that can't require a same-team peer doesn't connect")
    func malformedTeamRefuses() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.badTeam")
        let echo = EchoListener(queue: queue, response: .start)
        let endpoint = echo.endpoint
        let connection = LegacyXPCConnection(
            serviceName: "test",
            queue: queue,
            teamIdentifier: "bad",
            diagLog: DiagLog(category: "LegacyXPCConnectionTests"),
            onInvalidate: {},
            makeConnection: { _ in xpc_connection_create_from_endpoint(endpoint.object) }
        )

        #expect(await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self) == nil)
    }

    @Test("A service that goes away reports the invalidation and the next send reconnects")
    func serviceGoesAway() async throws {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.goesAway")
        let invalidations = OSAllocatedUnfairLock(initialState: 0)
        var echo: EchoListener? = EchoListener(queue: queue, response: .start)
        let connection = try Self.makeConnection(to: #require(echo), queue: queue) {
            invalidations.withLock { $0 += 1 }
        }
        defer { connection.cancel() }

        #expect(await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self) == .start)
        echo = nil
        for _ in 0 ..< 100 where invalidations.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(invalidations.withLock { $0 } == 1)
        #expect(await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self) == nil)
    }

    @Test("Concurrent first sends share one connection and both get a response")
    func concurrentFirstSends() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.concurrent")
        let echo = EchoListener(queue: queue, response: .start)
        let connection = Self.makeConnection(to: echo, queue: queue)
        defer { connection.cancel() }

        async let first = connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self)
        async let second = connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self)

        #expect(await [first, second] == [.start, .start])
    }

    @Test("A connection superseded while it's being made is dropped and the next send connects")
    func supersededConnectionIsDropped() async {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.superseded")
        let echo = EchoListener(queue: queue, response: .start)
        let endpoint = echo.endpoint
        let made = OSAllocatedUnfairLock(initialState: 0)
        let owner = OSAllocatedUnfairLock<LegacyXPCConnection?>(initialState: nil)
        let connection = LegacyXPCConnection(
            serviceName: "test",
            queue: queue,
            teamIdentifier: nil,
            diagLog: DiagLog(category: "LegacyXPCConnectionTests"),
            onInvalidate: {},
            makeConnection: { queue in
                let count = made.withLock { count in
                    count += 1
                    return count
                }
                // The first connection loses to a cancel that lands while it is being made.
                if count == 1 {
                    owner.withLock { $0 }?.cancel()
                }
                let connection = xpc_connection_create_from_endpoint(endpoint.object)
                xpc_connection_set_target_queue(connection, queue)
                return connection
            }
        )
        owner.withLock { $0 = connection }
        defer {
            owner.withLock { $0 = nil }
            connection.cancel()
        }

        #expect(await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self) == nil)
        #expect(await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self) == .start)
        #expect(made.withLock { $0 } == 2)
    }

    @Test("A service that is already gone reports the invalidation and the next send reconnects")
    func serviceGoneBeforeFirstSend() async throws {
        let queue = DispatchQueue(label: "LegacyXPCConnectionTests.goneFirst")
        let endpoint = EchoListener(queue: queue, response: .start).endpoint
        let made = OSAllocatedUnfairLock(initialState: 0)
        let invalidations = OSAllocatedUnfairLock(initialState: 0)
        let connection = LegacyXPCConnection(
            serviceName: "test",
            queue: queue,
            teamIdentifier: nil,
            diagLog: DiagLog(category: "LegacyXPCConnectionTests"),
            onInvalidate: { invalidations.withLock { $0 += 1 } },
            makeConnection: { queue in
                made.withLock { $0 += 1 }
                let connection = xpc_connection_create_from_endpoint(endpoint.object)
                xpc_connection_set_target_queue(connection, queue)
                return connection
            }
        )
        defer { connection.cancel() }

        #expect(await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self) == nil)
        for _ in 0 ..< 100 where invalidations.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(invalidations.withLock { $0 } == 1)
        _ = await connection.send(MenuBarCaptureService.Request.start, as: MenuBarCaptureService.Response.self)
        #expect(made.withLock { $0 } == 2)
    }
}
