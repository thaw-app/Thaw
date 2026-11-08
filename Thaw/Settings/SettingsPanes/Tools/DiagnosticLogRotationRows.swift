//
//  DiagnosticLogRotationRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Thaw 2's log size, retention and rotation settings, one native row each.
struct DiagnosticLogRotationRows: View {
    @Bindable var settings: ToolsSettings

    static let sizeRange = 1 ... 100
    static let retentionRange = 1 ... 30

    var body: some View {
        LabeledContent("Maximum file size") {
            Stepper(value: $settings.diagnosticLogMaxSizeMB, in: Self.sizeRange) {
                Text("\(settings.diagnosticLogMaxSizeMB) MB")
                    .monospacedDigit()
            }
            .fixedSize()
            .help("1 to 100 MB")
        }
        .settingsSearchAnchor("tools.diagnosticLogMaxSizeMB")

        LabeledContent("Delete logs after") {
            Stepper(value: $settings.diagnosticLogRetentionDays, in: Self.retentionRange) {
                Text(Self.days(settings.diagnosticLogRetentionDays))
                    .monospacedDigit()
            }
            .fixedSize()
            .help("1 to 30 days")
        }
        .settingsSearchAnchor("tools.diagnosticLogRetentionDays")

        ThawPicker("Start a new file", selection: $settings.diagnosticLogRotationInterval) {
            ForEach(LogRotationInterval.allCases) { interval in
                Text(interval.localized).tag(interval)
            }
        }
        .annotation("Thaw keeps at most the 50 newest logs, and never deletes the one it is writing.")
        .settingsSearchAnchor("tools.diagnosticLogRotationInterval")
    }

    static func days(_ count: Int) -> String {
        String(AttributedString(localized: "^[\(count) day](inflect: true)").characters)
    }
}
