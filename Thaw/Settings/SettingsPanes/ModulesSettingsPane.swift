//
//  ModulesSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// The optional parts of Thaw that run as their own apps. Each row switches
/// one on or off; a module that's off doesn't run at all.
struct ModulesSettingsPane: View {
    @Bindable var moduleHost: ModuleHost

    var body: some View {
        ThawForm {
            if rows.isEmpty {
                ThawSection {
                    ThawEmptyState(
                        systemImage: "puzzlepiece.extension",
                        title: "No modules",
                        caption: "This copy of \(Constants.displayName) came without any modules."
                    )
                }
            } else {
                ThawSection {
                    ForEach(rows, id: \.url) { row in
                        moduleRow(row)
                    }
                }
            }
        }
        .onAppear { moduleHost.refresh() }
    }

    private struct Row {
        let url: URL
        let manifest: ModuleManifest
        let state: ModuleHost.State
    }

    private var rows: [Row] {
        moduleHost.modules
            .compactMap { url, module in module.manifest.map { Row(url: url, manifest: $0, state: module.state) } }
            .sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
    }

    private func moduleRow(_ row: Row) -> some View {
        LabeledContent {
            ModuleControls(moduleHost: moduleHost, identifier: row.manifest.identifier, name: row.manifest.name)
        } label: {
            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text(verbatim: row.manifest.name)
                Text(Self.summary(for: row.manifest.identifier, state: row.state))
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
            }
        }
    }

    /// What a module does, or why it isn't running when it should be.
    static func summary(for identifier: String, state: ModuleHost.State) -> LocalizedStringKey {
        switch state {
        case .refused(.untrusted):
            return "Not signed by \(Constants.displayName)'s developers, so it won't run."
        case .refused(.needsNewerThaw):
            return "Needs a newer version of \(Constants.displayName)."
        case .gaveUp:
            return "Stopped after it kept quitting. Switch it off and on to try again."
        case .launchFailed:
            return "Couldn't start. Switch it off and on to try again."
        case .idle, .running, .restarting, .stopped, .refused(.launch), .refused(.notAModule):
            switch ModuleIdentifier(rawValue: identifier) {
            case .scripts: return "Runs your scripts when a profile switches."
            case .triggers: return "Shows chosen menu bar items while an app runs."
            case .widgets: return "Shows battery, Wi-Fi and other readings in one menu bar icon."
            case nil: return ""
            }
        }
    }
}
