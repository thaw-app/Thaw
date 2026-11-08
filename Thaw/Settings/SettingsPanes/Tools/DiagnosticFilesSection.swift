//
//  DiagnosticFilesSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

/// The files to attach to a bug report, as two rows like Repair's: the logs,
/// and the item list with its capture samples.
struct DiagnosticFilesSection: View {
    @State private var isExporting = false
    @State private var errorMessage: String?
    /// Read when the section appears, since samples are written while Thaw runs.
    @State private var hasCaptureSamples = false

    var body: some View {
        ThawSection("Files for a bug report") {
            LabeledContent {
                HStack(spacing: ThawSpacing.base) {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    }
                    ThawActionGroup {
                        Button("Show in Finder") {
                            NSWorkspace.shared.open(DiagnosticLogger.shared.logDirectory)
                        }
                        .accessibilityLabel("Show Log Files in Finder")
                        Button("Export…", action: exportLogs)
                            .disabled(isExporting)
                            .accessibilityLabel("Export Logs")
                    }
                    .buttonStyle(.thawGrouped)
                }
            } label: {
                ThawRowLabel("Logs", detail: "Export zips the logs and any capture samples into one file to attach.")
            }

            LabeledContent {
                ThawActionGroup {
                    Button("Save…", action: saveItemList)
                        .accessibilityLabel("Save Item List")
                    Button("Show Samples") {
                        NSWorkspace.shared.open(CaptureDiagnostics.sampleDirectory)
                    }
                    .disabled(!hasCaptureSamples)
                    .accessibilityLabel("Show Capture Samples")
                }
                .buttonStyle(.thawGrouped)
            } label: {
                ThawRowLabel("Item list", detail: "Every menu bar item Thaw can see. Samples are the pictures it captured.")
            }
        }
        .onAppear {
            hasCaptureSamples = MaintenanceTools.hasCaptureSamples(in: CaptureDiagnostics.sampleDirectory)
        }
        .alert(
            "Couldn’t save the file",
            isPresented: Binding(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportLogs() {
        guard let destination = Self.chooseDestination(name: "\(Constants.displayName) Diagnostics.zip", type: .zip) else {
            return
        }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                try await MaintenanceTools.exportDiagnostics(
                    logs: DiagnosticLogger.shared.logDirectory,
                    samples: CaptureDiagnostics.sampleDirectory,
                    to: destination
                )
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveItemList() {
        guard let destination = Self.chooseDestination(name: "\(Constants.displayName) Items.json", type: .json) else {
            return
        }
        do {
            try MaintenanceTools.saveItemList(to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func chooseDestination(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
