//
//  ModuleOpenRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// A module's own controls: its on/off switch, and Open… while it is on.
/// A module that isn't installed says so instead of offering a switch that
/// can do nothing.
struct ModuleControls: View {
    @Bindable var moduleHost: ModuleHost
    let identifier: String
    let name: String

    var body: some View {
        HStack(spacing: ThawSpacing.base) {
            if let url = moduleHost.url(ofModule: identifier) {
                if moduleHost.isEnabled(identifier) {
                    Button("Open…") { Task { await moduleHost.start(url, showingWindow: true) } }
                        .buttonStyle(.settingsGlass)
                }
                Toggle(isOn: Binding(
                    get: { moduleHost.isEnabled(identifier) },
                    set: { enabled in Task { await moduleHost.setEnabled(enabled, identifier: identifier) } }
                )) {
                    Text(verbatim: name)
                }
                .labelsHidden()
                .toggleStyle(.switch)
            } else {
                Text("Not installed")
                    .foregroundStyle(ThawInk.supporting)
            }
        }
    }
}

/// A row for a feature that lives in a module, with the module's switch
/// right there, so the feature turns on where it is described.
struct ModuleOpenRow: View {
    @Environment(AppState.self) private var appState
    let module: ModuleIdentifier
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        LabeledContent {
            ModuleControls(
                moduleHost: appState.moduleHost,
                identifier: module.rawValue,
                name: appState.moduleHost.url(ofModule: module).flatMap { appState.moduleHost.modules[$0]?.manifest?.name } ?? module.rawValue
            )
        } label: {
            ThawRowLabel(title, detail: detail)
        }
    }
}
