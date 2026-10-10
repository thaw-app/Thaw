//
//  MovePipelineMonitor.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Observation

/// An in-memory record of what the reorder pipeline actually did, surfaced in
/// the Privacy settings pane next to the capture inspector.
///
/// The capture inspector's rule applies here too: the records are structural,
/// not aspirational. Every entry is written by the very code paths that move
/// items, the preferred-position write and the synthetic-drag engine, so
/// the pane cannot describe a reorder any other way than it happened.
///
/// Records live in memory only: nothing here reaches disk, logs, or the
/// network, and entries exist only because a reorder ran.
@MainActor
@Observable
final class MovePipelineMonitor {
    /// One delivery attempt of a synthetic drag.
    struct Attempt: Identifiable {
        let id = UUID()
        /// Where the attempt was addressed, the same descriptions the
        /// diagnostics log uses ("event record pid 412", "hidEventTap").
        let addressDescription: String
        /// Whether the requested order was verified after this attempt.
        let landed: Bool
    }

    /// One completed pass through the pipeline for one item.
    struct MoveRecord: Identifiable {
        let id = UUID()
        let date: Date
        let itemDescription: String
        let destinationDescription: String
        /// How the move was enacted: a preferred-position write or a
        /// synthetic Command-drag.
        let channelDescription: String
        let attempts: [Attempt]
        let duration: Duration?
        let succeeded: Bool
    }

    /// Cursor-free store writes this session.
    private(set) var storeMoveCount = 0
    /// Synthetic drags this session.
    private(set) var dragMoveCount = 0
    private(set) var eventRecordAttemptCount = 0
    private(set) var eventRecordLandCount = 0
    private(set) var hidAttemptCount = 0
    private(set) var hidLandCount = 0
    /// Set the first time a move finds the position table unreachable (the
    /// macOS 27 protected container without Full Disk Access).
    private(set) var sawStoreUnavailable = false

    /// Newest first, capped: the pane shows recent history, not an audit log.
    private(set) var records: [MoveRecord] = []

    private static let recordLimit = 25

    func recordStoreMove(item: String, destination: String, satisfied: Bool) {
        storeMoveCount += 1
        insert(
            MoveRecord(
                date: .now,
                itemDescription: item,
                destinationDescription: destination,
                channelDescription: "preferred positions",
                attempts: [],
                duration: nil,
                succeeded: satisfied
            )
        )
    }

    /// Marks that a move wanted the position table and could not reach it.
    func recordStoreUnavailable() {
        sawStoreUnavailable = true
    }

    func recordDragMove(
        item: String,
        destination: String,
        attempts: [(address: SyntheticMoveEngine.DragAddress, landed: Bool)],
        duration: Duration,
        succeeded: Bool
    ) {
        dragMoveCount += 1
        let mappedAttempts = attempts.map { attempt in
            Attempt(addressDescription: attempt.address.description, landed: attempt.landed)
        }
        for attempt in attempts {
            switch attempt.address {
            case .eventRecord:
                eventRecordAttemptCount += 1
                if attempt.landed {
                    eventRecordLandCount += 1
                }
            case .hidEventTap, .process:
                hidAttemptCount += 1
                if attempt.landed {
                    hidLandCount += 1
                }
            }
        }
        insert(
            MoveRecord(
                date: .now,
                itemDescription: item,
                destinationDescription: destination,
                channelDescription: "command-drag",
                attempts: mappedAttempts,
                duration: duration,
                succeeded: succeeded
            )
        )
    }

    private func insert(_ record: MoveRecord) {
        records.insert(record, at: 0)
        if records.count > Self.recordLimit {
            records.removeLast(records.count - Self.recordLimit)
        }
    }
}
