//
//  MoveResultMessage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

/// The short message shown after a move chosen from an item's menu, which
/// says what happened, including when the item did not move.
nonisolated struct MoveResultMessage: Equatable {
    let symbol: String
    let text: String

    /// - Parameters:
    ///   - committed: Whether the section change was made at all.
    ///   - landed: Whether the item is in the target section afterwards.
    static func make(itemName: String, sectionTitle: String, committed: Bool, landed: Bool) -> MoveResultMessage {
        switch (committed, landed) {
        case (true, true):
            MoveResultMessage(symbol: "checkmark", text: String(localized: "Moved \(itemName) to \(sectionTitle)"))
        case (true, false):
            MoveResultMessage(
                symbol: "exclamationmark.triangle",
                text: String(localized: "\(itemName) didn’t stay in \(sectionTitle)")
            )
        case (false, _):
            MoveResultMessage(symbol: "exclamationmark.triangle", text: String(localized: "Couldn’t move \(itemName)"))
        }
    }
}
