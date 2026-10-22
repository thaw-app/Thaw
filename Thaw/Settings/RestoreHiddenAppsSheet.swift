//
//  RestoreHiddenAppsSheet.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// Lists apps that are switched off in System Settings with no record of who
/// did it, none selected, so the user picks the ones to show.
struct RestoreHiddenAppsSheet: View {
    @Bindable var offer: HiddenAppsRestoreOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore apps \(Constants.displayName) hid")
                .font(.title2.bold())

            Text("These apps are switched off in System Settings \(Constants.menuArrow) Menu Bar. An older version of \(Constants.displayName) may have switched them off, or you may have, and \(Constants.displayName) can't tell which. Select the ones you want back in the menu bar.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                    ForEach(offer.candidates, id: \.self) { bundleID in
                        candidateRow(bundleID)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)

            if let error = offer.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Keep Hidden") { offer.keepHidden() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.settingsGlass)
                Button("Show Selected") { offer.showSelected() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.thawProminent)
                    .disabled(offer.selectedBundleIDs.isEmpty)
            }
        }
        .padding(20)
        // A minimum, not a width: the buttons and body copy are translated.
        .frame(minWidth: 420)
    }

    private func candidateRow(_ bundleID: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        return Toggle(isOn: selection(for: bundleID)) {
            HStack(spacing: ThawSpacing.compact) {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading) {
                    Text(verbatim: NativeVisibilityRecoveryLaunch.displayName(forBundleID: bundleID, applicationURL: url))
                    Text(verbatim: bundleID)
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                }
            }
        }
        .toggleStyle(.thawCheckbox)
    }

    private func selection(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { offer.selectedBundleIDs.contains(bundleID) },
            set: { selected in
                if selected {
                    offer.selectedBundleIDs.insert(bundleID)
                } else {
                    offer.selectedBundleIDs.remove(bundleID)
                }
            }
        )
    }
}
