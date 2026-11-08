//
//  DiagnosticFilesRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

/// The files to attach to a bug report: the logs, an item list and capture samples.
struct DiagnosticFilesRow: View {
    @State private var isExporting = false
    @State private var errorMessage: String?
    /// Read when the row appears, since samples are written while Thaw runs.
    @State private var hasCaptureSamples = false

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            HStack(spacing: ThawSpacing.inset) {
                Button("Show Log Files in Finder") {
                    NSWorkspace.shared.open(DiagnosticLogger.shared.logDirectory)
                }
                Button("Export Logs…", action: exportLogs)
                    .disabled(isExporting)
                if isExporting {
                    ProgressView().controlSize(.small)
                }
            }
            HStack(spacing: ThawSpacing.inset) {
                Button("Save Item List…", action: saveItemList)
                Button("Show Capture Samples") {
                    NSWorkspace.shared.open(CaptureDiagnostics.sampleDirectory)
                }
                .disabled(!hasCaptureSamples)
            }
        }
        .buttonStyle(.settingsGlass)
        .annotation {
            Text("Export Logs zips the logs and any capture samples into one file for a bug report. The item list records every menu bar item Thaw can see.")
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
