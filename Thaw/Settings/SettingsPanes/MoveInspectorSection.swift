//
//  MoveInspectorSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Shows what the reorder pipeline actually did, the same records the
/// pipeline itself writes, so this page cannot describe a move any other way
/// than it happened.
///
/// Lives on Tools under Diagnostics, shown only while diagnostic logging is
/// on, because it reads as the log's live view. The framing still mirrors the
/// capture inspector: moves are recorded when they happen (never on a timer),
/// the records are memory-only, and the copy states the physical scope
/// exactly, which attempts move the real pointer and which never touch it.
struct MoveInspectorSection: View {
    @Environment(AppState.self) var appState

    var body: some View {
        ThawSection("Recent item moves") {
            scopeDescription
            channelMode
            if !moveMonitor.records.isEmpty {
                counters
                moveList
            }
        }
    }

    private var moveMonitor: MovePipelineMonitor {
        appState.itemManager.moveMonitor
    }

    /// The scope statement: moves happen only on reorder actions, the record
    /// is the pipeline's own, and it never leaves memory.
    private var scopeDescription: some View {
        Text(
            """
            Each time \(Constants.displayName) moves a menu bar item, the move is \
            listed here, the same record the diagnostic log keeps. Moves happen only \
            when you reorder. The list lives in memory only and is never saved to \
            disk or sent anywhere.
            """
        )
        .font(ThawType.footnote)
        .foregroundStyle(ThawInk.supporting)
    }

    /// Which channel moves items right now, and the honest reason why.
    @ViewBuilder
    private var channelMode: some View {
        let storeInert = appState.itemManager.menuBarAgentIgnoresPreferredPositions
        Label {
            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text(
                    storeInert
                        ? "Items are moved with the pointer"
                        : "Items are moved by updating macOS's saved menu bar layout"
                )
                Text(
                    storeInert
                        ? "While an item is dragged into place, the pointer is hidden and your mouse input is held, then both come back."
                        : "Your pointer never moves: the saved layout is updated and the menu bar re-sorts itself."
                )
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
                if moveMonitor.sawStoreUnavailable {
                    Text("macOS refused access to its saved menu bar layout this session. Grant Menu Bar Layout Access on the Privacy page.")
                        .font(ThawType.micro)
                        .foregroundStyle(ThawInk.supporting)
                }
            }
        } icon: {
            Image(systemName: storeInert ? "hand.draw" : "tablecells")
                .foregroundStyle(.secondary)
        }
    }

    /// The glanceable answer to "is the cursor-free path working?"
    private var counters: some View {
        LabeledContent("This session") {
            VStack(alignment: .trailing, spacing: ThawSpacing.hairline) {
                Text("\(moveMonitor.storeMoveCount) layout updates")
                Text("\(moveMonitor.dragMoveCount) pointer moves")
                Text(cursorFreeSummary)
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            }
            .monospacedDigit()
        }
    }

    private var cursorFreeSummary: String {
        let total = moveMonitor.eventRecordAttemptCount
        guard total > 0 else {
            return String(localized: "Moves without the pointer: none yet")
        }
        return String(localized: "Moves without the pointer: \(moveMonitor.eventRecordLandCount) of \(total) worked")
    }

    private var moveList: some View {
        ForEach(moveMonitor.records) { record in
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                HStack(alignment: .firstTextBaseline) {
                    Image(
                        systemName: record.succeeded
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .foregroundStyle(record.succeeded ? Color.green : Color.red)
                    Text(record.itemDescription)
                        .lineLimit(1)
                    Spacer()
                    Text(record.date, style: .time)
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                }
                Text(record.destinationDescription)
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
                    .lineLimit(1)
                if !record.attempts.isEmpty {
                    Text(attemptSummary(for: record))
                        .font(ThawType.micro)
                        .foregroundStyle(ThawInk.supporting)
                }
                if let duration = record.duration {
                    Text("Took \(milliseconds(duration)) ms")
                        .font(ThawType.micro)
                        .foregroundStyle(ThawInk.supporting)
                }
            }
            .padding(.vertical, ThawSpacing.hairline)
        }
    }

    private func attemptSummary(for record: MovePipelineMonitor.MoveRecord) -> String {
        record.attempts
            .map { attempt in
                let outcome = attempt.landed
                    ? String(localized: "moved")
                    : String(localized: "no effect")
                return "\(attempt.addressDescription): \(outcome)"
            }
            .joined(separator: " · ")
    }

    private func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds) * 1000
            + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}

/// The disclaimer: privacy work only counts if a human answers questions.
/// Sits with the transparency surfaces it refers to.
struct PrivacyQuestionsDisclaimer: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.base) {
            Label("Privacy questions are welcome", systemImage: "questionmark.bubble")
                .font(ThawType.heading)
            Text(
                """
                Ask us about anything on this page: what \(Constants.displayName) reads, what it \
                writes, why it asks for a permission, or how it moves your items. \
                We are open to any question about privacy, and every one gets \
                an answer from a person.
                """
            )
            .font(ThawType.footnote)
            .foregroundStyle(ThawInk.supporting)
            Button {
                openURL(Constants.discordURL)
            } label: {
                Label("Ask on Discord", systemImage: "bubble.left")
            }
            .buttonStyle(.settingsGlass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ThawSpacing.tight)
    }
}
