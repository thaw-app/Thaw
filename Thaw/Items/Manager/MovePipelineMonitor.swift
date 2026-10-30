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
/// not aspirational. Every entry is written by the preferred-position write
/// that moves items, so the pane cannot describe a reorder any other way than
/// it happened.
///
/// Records live in memory only: nothing here reaches disk, logs, or the
/// network, and entries exist only because a reorder ran.
@MainActor
@Observable
final class MovePipelineMonitor {
    /// One completed pass through the pipeline for one item.
    struct MoveRecord: Identifiable {
        let id = UUID()
        let date: Date
        let itemDescription: String
        let destinationDescription: String
        let succeeded: Bool
    }

    /// Cursor-free store writes this session.
    private(set) var storeMoveCount = 0
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
                succeeded: satisfied
            )
        )
    }

    /// Marks that a move wanted the position table and could not reach it.
    func recordStoreUnavailable() {
        sawStoreUnavailable = true
    }

    private func insert(_ record: MoveRecord) {
        records.insert(record, at: 0)
        if records.count > Self.recordLimit {
            records.removeLast(records.count - Self.recordLimit)
        }
    }
}
