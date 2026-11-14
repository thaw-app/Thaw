//
//  DiagnosticFilesSection+Actions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import UniformTypeIdentifiers

extension DiagnosticFilesSection {
    /// What the section's buttons reach outside the view. Tests supply their own,
    /// so no panel opens, Finder stays put and no real log is copied.
    struct Actions {
        var chooseDestination: @MainActor (_ suggestedName: String, _ type: UTType) -> URL? = { suggestedName, type in
            let panel = NSSavePanel()
            panel.allowedContentTypes = [type]
            panel.nameFieldStringValue = suggestedName
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }

        /// Opens a folder in Finder.
        var open: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }

        /// Shows a written file selected in Finder.
        var reveal: @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

        var exportDiagnostics: (URL) async throws -> Void = { destination in
            try await MaintenanceTools.exportDiagnostics(
                logs: DiagnosticLogger.shared.logDirectory,
                samples: CaptureDiagnostics.sampleDirectory,
                to: destination
            )
        }

        var saveItemList: @MainActor (URL) throws -> Void = { try MaintenanceTools.saveItemList(to: $0) }
    }
}
