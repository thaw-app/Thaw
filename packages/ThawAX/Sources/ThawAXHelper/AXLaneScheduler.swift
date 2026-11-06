//
//  AXLaneScheduler.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import ThawAXCore

/// Independent lanes run one request at a time under AXLane's waiting policy.
/// Dedicated threads keep blocking AX IPC from starving the cooperative pool when an app hangs.
final class AXLaneScheduler: @unchecked Sendable {
    typealias Serve = @Sendable (AXHelperRequest) -> AXHelperReply
    typealias Emit = @Sendable (AXReplyFrame) -> Void

    private final class Lane: @unchecked Sendable {
        let kind: AXLane
        private let condition = NSCondition()
        /// Guarded by condition; each entry lists all frame IDs answered by one run.
        private var waiting: [(ids: [UInt64], request: AXHelperRequest)] = []
        private var isClosed = false

        init(kind: AXLane) {
            self.kind = kind
        }

        /// Queues frame under the lane's policy. Returns the ids the policy
        /// dropped, which the caller answers as superseded.
        func enqueue(_ frame: AXRequestFrame) -> [UInt64] {
            condition.lock()
            defer {
                condition.signal()
                condition.unlock()
            }
            switch kind {
            case .pointer:
                // Latest wins: whatever is still waiting is stale.
                let dropped = waiting.flatMap(\.ids)
                waiting = [([frame.id], frame.request)]
                return dropped
            case .walk, .menu:
                // Share: an identical waiting request answers this one too.
                if let index = waiting.firstIndex(where: { $0.request == frame.request }) {
                    waiting[index].ids.append(frame.id)
                } else {
                    waiting.append(([frame.id], frame.request))
                }
                return []
            case .press:
                waiting.append(([frame.id], frame.request))
                return []
            }
        }

        /// Blocks until work arrives, or returns nil once the lane is closed
        /// and drained.
        func next() -> (ids: [UInt64], request: AXHelperRequest)? {
            condition.lock()
            defer { condition.unlock() }
            while waiting.isEmpty, !isClosed {
                condition.wait()
            }
            return waiting.isEmpty ? nil : waiting.removeFirst()
        }

        func close() {
            condition.lock()
            isClosed = true
            condition.broadcast()
            condition.unlock()
        }
    }

    private let lanes: [AXLane: Lane]
    private let threads: [Thread]
    /// Signalled once per lane thread as it runs out of work after close().
    private let drained = DispatchSemaphore(value: 0)
    private let serve: Serve
    private let emit: Emit

    init(serve: @escaping Serve, emit: @escaping Emit) {
        self.serve = serve
        self.emit = emit
        var lanes: [AXLane: Lane] = [:]
        for kind in AXLane.allCases {
            lanes[kind] = Lane(kind: kind)
        }
        self.lanes = lanes
        let drained = drained
        threads = AXLane.allCases.map { kind in
            let lane = lanes[kind]!
            let thread = Thread {
                while let work = lane.next() {
                    // Long-lived lane threads need explicit pools to drain AX and NSWorkspace autoreleased objects.
                    autoreleasepool {
                        let reply = serve(work.request)
                        for id in work.ids {
                            emit(AXReplyFrame(id: id, outcome: .reply(reply)))
                        }
                    }
                }
                drained.signal()
            }
            thread.name = "ThawAXHelper.\(kind.rawValue)"
            thread.qualityOfService = kind == .walk ? .utility : .userInteractive
            return thread
        }
        threads.forEach { $0.start() }
    }

    func submit(_ frame: AXRequestFrame) {
        guard let lane = lanes[frame.request.lane] else { return }
        for id in lane.enqueue(frame) {
            emit(AXReplyFrame(id: id, outcome: .superseded))
        }
    }

    /// Stops accepting work and returns once every lane has answered what was
    /// already queued.
    func closeAndDrain() {
        lanes.values.forEach { $0.close() }
        for _ in threads {
            drained.wait()
        }
    }
}
