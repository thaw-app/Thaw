//
//  ProfileSettingsPane+FileChoosers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import UniformTypeIdentifiers

extension ProfileSettingsPane {
    /// The panels the page opens to choose a file. Tests supply their own, so none opens.
    struct FileChoosers {
        var save: @MainActor (_ suggestedName: String) -> URL? = { suggestedName in
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = suggestedName
            panel.canCreateDirectories = true
            return panel.runModal() == .OK ? panel.url : nil
        }

        var open: @MainActor () -> URL? = {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
}
