//
//  StoreWritePermit.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel

/// Proof that a caller was let in before it writes the position table.
///
/// The table has one writer at a time, and the two doors that guarantee it are
/// the repair lane and the move permit. Every write function asks for one of
/// these, so a write that came through neither door does not compile. It cannot
/// be copied, so it cannot be kept and spent after the door has closed.
///
/// A third door, ``unsequenced(_:)``, exists for the writers that still come
/// through neither. It serializes nothing. It names the path so the remaining
/// ones can be counted and routed, and it is meant to reach zero uses.
struct StoreWritePermit: ~Copyable {
    /// How the holder got in.
    enum Door: Equatable, CustomStringConvertible {
        /// Admitted by ``RepairLane``.
        case repairLane(RepairOrchestrator.Work)
        /// Inside the move permit, see ``SimpleSemaphore/withStoreWritePermit(isolation:_:)``.
        case moveMutation
        /// Through neither door.
        case unsequenced(String)

        var description: String {
            switch self {
            case let .repairLane(work): "repairLane(\(work.rawValue))"
            case .moveMutation: "moveMutation"
            case let .unsequenced(path): "unsequenced(\(path))"
            }
        }
    }

    let door: Door

    fileprivate init(door: Door) {
        self.door = door
    }

    /// For a pass the lane has admitted.
    init(_ hold: RepairLane.Hold) {
        self.init(door: .repairLane(hold.work))
    }

    /// For a writer that does not yet come through a door. `path` names it.
    static func unsequenced(_ path: String) -> StoreWritePermit {
        StoreWritePermit(door: .unsequenced(path))
    }
}

extension SimpleSemaphore {
    /// Runs an operation inside one permit of this semaphore and hands it the
    /// right to write the position table for as long as it holds that permit.
    func withStoreWritePermit<Result: Sendable>(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: (borrowing StoreWritePermit) async throws -> Result
    ) async throws -> Result {
        try await withPermit(isolation: isolation) {
            try await operation(StoreWritePermit(door: .moveMutation))
        }
    }
}

/// Counts position-table writes by the door they came through.
@MainActor
enum StoreWriteAudit {
    private static let diagLog = DiagLog(category: "StoreWriteAudit")

    private(set) static var counts: [String: Int] = [:]

    static func note(_ permit: borrowing StoreWritePermit, write: String) {
        counts[permit.door.description, default: 0] += 1
        if case let .unsequenced(path) = permit.door {
            diagLog.debug("\(write) written outside both doors (\(path))")
        }
    }

    /// Writes that came through neither door, by path.
    static var unsequenced: [String: Int] {
        counts.filter { $0.key.hasPrefix("unsequenced(") }
    }
}
