//
//  DiagnosticFilesSection+Actions.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
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

        var saveItemList: @MainActor (URL) async throws -> Void = { try MaintenanceTools.saveItemList(to: $0) }
    }

    /// The section where Settings is shown. In the settings process the app writes the item list, since that
    /// reads other apps' menu bar items, and this process copies it to the place chosen in its save panel.
    @MainActor
    static func current(_ appState: AppState, remote: SettingsRemote? = .current) -> DiagnosticFilesSection {
        guard remote != nil else { return DiagnosticFilesSection() }
        let report = appState.settings.tools.appReport
        var actions = Actions()
        actions.exportDiagnostics = { destination in
            try await MaintenanceTools.exportDiagnostics(
                logs: DiagnosticLogger.shared.logDirectory,
                samples: report.status.sampleDirectory,
                to: destination
            )
        }
        actions.saveItemList = { destination in
            var list: URL?
            try await ToolsTasks.perform(.writeItemList, appState: appState, remote: remote, report: { event in
                if case let .itemList(written) = event {
                    list = written
                }
            })
            guard let list else { throw CocoaError(.fileWriteUnknown) }
            try MaintenanceTools.replaceItem(at: destination, withCopyOf: list)
        }
        return DiagnosticFilesSection(actions: actions, appReport: report)
    }
}
