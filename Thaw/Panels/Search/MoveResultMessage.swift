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
    /// What the notice adds for a failure: a move macOS undid, or one that never went through.
    var detail: String?

    var isFailure: Bool {
        symbol != "checkmark"
    }

    /// A failure stays up long enough to read; a success clears at the usual pace.
    var displayDuration: Duration {
        isFailure ? .seconds(3) : .milliseconds(1200)
    }

    /// A failure also goes to the Layout notice, which lasts longer and VoiceOver announces.
    var refusal: LayoutBarFeedbackCenter.Refusal? {
        guard isFailure, let detail else { return nil }
        return LayoutBarFeedbackCenter.Refusal(title: text, message: detail)
    }

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
                text: String(localized: "\(itemName) didn’t stay in \(sectionTitle)"),
                detail: String(localized: "macOS put it back. Try again, or move it in Settings \(Constants.menuArrow) Layout.")
            )
        case (false, _):
            MoveResultMessage(
                symbol: "exclamationmark.triangle",
                text: String(localized: "Couldn’t move \(itemName)"),
                detail: String(localized: "The move didn’t go through. Try again, or move it in Settings \(Constants.menuArrow) Layout.")
            )
        }
    }
}
