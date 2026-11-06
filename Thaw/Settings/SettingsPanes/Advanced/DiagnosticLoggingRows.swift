//
//  DiagnosticLoggingRows.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The diagnostic logging switch with its size, retention and rotation options.
struct DiagnosticLoggingRows: View {
    @Bindable var settings: AdvancedSettings
    @State private var currentLogFileName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Enable diagnostic logging",
                isOn: $settings.enableDiagnosticLogging
            )
            .annotation {
                Text(
                    """
                    Writes detailed debug logs to a file for troubleshooting. \
                    Log files are saved to ~/Library/Logs/Thaw/. \
                    Disable when not needed to avoid unnecessary disk writes.
                    """
                )
                .padding(.trailing, 75)
            }

            if settings.enableDiagnosticLogging {
                LabeledContent("Maximum log file size (MB)") {
                    numberField(
                        "Maximum log file size in megabytes",
                        value: $settings.diagnosticLogMaxSizeMB,
                        bounds: Self.logSizeBounds
                    )
                }
                .annotation("Start a new log file once the current one reaches this size.")

                LabeledContent("Keep logs for (days)") {
                    numberField(
                        "Days to keep log files",
                        value: $settings.diagnosticLogRetentionDays,
                        bounds: Self.logRetentionBounds
                    )
                }
                .annotation {
                    Text(
                        """
                        Delete older log files after this many days, or sooner if more than 50 pile up. \
                        The file being written is always kept.
                        """
                    )
                }

                IcePicker("Rotate by time", selection: $settings.diagnosticLogRotationInterval) {
                    ForEach(LogRotationInterval.allCases) { interval in
                        Text(interval.localized).tag(interval)
                    }
                }
                .annotation {
                    Text(
                        """
                        Also start a new log file once the current one has been open for an hour or a day. \
                        The size limit still applies.
                        """
                    )
                }
            }

            HStack(spacing: 12) {
                if settings.enableDiagnosticLogging || DiagnosticLogger.shared.hasLogFiles {
                    Button("Show Log Files in Finder") {
                        let url = DiagnosticLogger.shared.logDirectory
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.thawSecondary)
                }

                if let currentLogFileName {
                    Text(currentLogFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: settings.enableDiagnosticLogging) {
                // Yield so the settings observer can create or close the log file first.
                try? await Task.sleep(for: .milliseconds(50))
                currentLogFileName = (
                    DiagnosticLogger.shared.currentLogFile
                        ?? DiagnosticLogger.shared.latestLogFile
                )?.lastPathComponent
            }
        }
    }

    /// A number the user can type or step through; both controls share a hidden label for VoiceOver.
    private func numberField(
        _ label: LocalizedStringKey,
        value: Binding<Int>,
        bounds: NumberBounds
    ) -> some View {
        HStack(spacing: 6) {
            TextField(label, value: value, formatter: bounds.formatter)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()

            Stepper(label, value: value, in: bounds.range)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    /// A stepper's range together with the formatter that holds typed input
    /// inside it, so the two cannot drift apart.
    private struct NumberBounds {
        let range: ClosedRange<Int>
        let formatter: NumberFormatter

        init(_ range: ClosedRange<Int>) {
            self.range = range

            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            formatter.allowsFloats = false
            formatter.minimum = NSNumber(value: range.lowerBound)
            formatter.maximum = NSNumber(value: range.upperBound)
            self.formatter = formatter
        }
    }

    private static let logSizeBounds = NumberBounds(1 ... 100)
    private static let logRetentionBounds = NumberBounds(1 ... 30)
}
