//
//  DiagnosticLogRotationRows.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Thaw 2's log size, retention and rotation settings, in its ranges.
struct DiagnosticLogRotationRows: View {
    @Bindable var settings: ToolsSettings

    static let sizeRange = 1 ... 100
    static let retentionRange = 1 ... 30

    var body: some View {
        LabeledContent("Maximum log file size") {
            Stepper(value: $settings.diagnosticLogMaxSizeMB, in: Self.sizeRange) {
                Text("\(settings.diagnosticLogMaxSizeMB) MB")
                    .monospacedDigit()
            }
        }
        .annotation("A new log file starts once the current one reaches this size.")

        LabeledContent("Keep logs for") {
            Stepper(value: $settings.diagnosticLogRetentionDays, in: Self.retentionRange) {
                Text("\(settings.diagnosticLogRetentionDays) days")
                    .monospacedDigit()
            }
        }
        .annotation("Thaw also deletes logs past the 50 newest. The current file always stays.")

        ThawPicker("Rotate by time", selection: $settings.diagnosticLogRotationInterval) {
            ForEach(LogRotationInterval.allCases) { interval in
                Text(interval.localized).tag(interval)
            }
        }
        .annotation("A new log file also starts after an hour or a day. The size limit still applies.")
    }
}
