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
/// exactly.
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

    /// How items are moved, and whether macOS let Thaw do it this session.
    private var channelMode: some View {
        Label {
            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text("Items are moved by updating macOS's saved menu bar layout")
                Text("Your pointer never moves: the saved layout is updated and the menu bar re-sorts itself.")
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
                if moveMonitor.sawStoreUnavailable {
                    Text("macOS refused access to its saved menu bar layout this session. Grant Menu Bar Layout Access on the Privacy page.")
                        .font(ThawType.micro)
                        .foregroundStyle(ThawInk.supporting)
                }
            }
        } icon: {
            Image(systemName: "tablecells")
                .foregroundStyle(.secondary)
        }
    }

    /// The glanceable answer to "is the cursor-free path working?"
    private var counters: some View {
        LabeledContent("This session") {
            Text("\(moveMonitor.storeMoveCount) layout updates")
                .monospacedDigit()
        }
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
            }
            .padding(.vertical, ThawSpacing.hairline)
        }
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
