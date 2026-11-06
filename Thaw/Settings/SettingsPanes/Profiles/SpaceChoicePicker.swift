//
//  SpaceChoicePicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// Chooses a Space by its persistent key, grouped by display as Mission Control shows them.
/// An empty key means no Space.
struct SpaceChoicePicker: View {
    let groups: [SpaceDisplayGroup]
    let missing: [SpaceChoice]
    @Binding var selection: String
    var appIcon: (pid_t) -> NSImage? = { NSRunningApplication(processIdentifier: $0)?.icon }

    var body: some View {
        ThawPicker(selection: $selection) {
            Text("None").tag("")
            ForEach(groups) { group in
                Section(Self.header(for: group)) {
                    ForEach(group.spaces) { choice in
                        row(for: choice).tag(choice.id)
                    }
                }
            }
            if !missing.isEmpty {
                Section("Not available") {
                    ForEach(missing) { choice in
                        Text(Self.label(for: choice)).tag(choice.id)
                    }
                }
            }
        } label: {
            ThawRowLabel("In this Space", detail: "Switches when you go to it. Desktops are numbered as in Mission Control.")
        }
    }

    @ViewBuilder
    private func row(for choice: SpaceChoice) -> some View {
        if let pid = choice.ownerPID, let icon = appIcon(pid) {
            Label {
                Text(choice.label)
            } icon: {
                Image(nsImage: icon)
            }
        } else {
            Text(choice.label)
        }
    }

    /// A display's name, marked when it has the menu bar.
    static func header(for group: SpaceDisplayGroup) -> String {
        group.hasMenuBar
            ? String(localized: "\(group.displayName) · Has the menu bar", comment: "A display in the Space picker that shows the active menu bar.")
            : group.displayName
    }

    /// A Space a profile names but macOS no longer lists.
    static func label(for choice: SpaceChoice) -> String {
        choice.isMissing ? String(localized: "\(choice.label) · Missing", comment: "A Space that no longer exists.") : choice.label
    }
}
