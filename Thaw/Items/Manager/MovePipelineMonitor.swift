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
    nonisolated struct MoveRecord: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        let date: Date
        let itemDescription: String
        let destinationDescription: String
        let succeeded: Bool
    }

    /// Everything the monitor holds, as the app sends it to its settings process.
    nonisolated struct Snapshot: Codable, Equatable, Sendable {
        var storeMoveCount = 0
        var sawStoreUnavailable = false
        var records: [MoveRecord] = []
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

    var snapshot: Snapshot {
        Snapshot(storeMoveCount: storeMoveCount, sawStoreUnavailable: sawStoreUnavailable, records: records)
    }

    /// Shows the moves of the running app. The settings process moves nothing itself, so its
    /// monitor only ever holds what the app sent last.
    func show(_ snapshot: Snapshot) {
        storeMoveCount = snapshot.storeMoveCount
        sawStoreUnavailable = snapshot.sawStoreUnavailable
        records = Array(snapshot.records.prefix(Self.recordLimit))
    }

    private func insert(_ record: MoveRecord) {
        records.insert(record, at: 0)
        if records.count > Self.recordLimit {
            records.removeLast(records.count - Self.recordLimit)
        }
    }
}
