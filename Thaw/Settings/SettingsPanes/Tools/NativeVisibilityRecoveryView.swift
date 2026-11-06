//
//  NativeVisibilityRecoveryView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

struct NativeVisibilityRecoveryView: View {
    @State private var model = NativeVisibilityRecoveryModel.live()
    @State private var confirmsRestore = false
    @State private var confirmsSetAside = false
    @State private var confirmsBypass = false

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.gutter) {
            Text("Restore missing menu bar items")
                .font(ThawType.heading)
            Text("Normal hiding is stopped in this window. Recovery changes app visibility only, not your saved layout or positions.")
                .foregroundStyle(ThawInk.supporting)

            ScrollView {
                VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                    if model.isBusy {
                        ProgressView("Checking menu bar visibility…")
                    } else if let message = model.successMessage {
                        Text(message)
                        if !model.setAsideLocations.isEmpty {
                            setAsideNotice
                        }
                    } else if model.recordIsUnreadable {
                        unreadableRecord
                    } else if model.hasLoaded {
                        if !model.setAsideLocations.isEmpty {
                            setAsideNotice
                        }
                        if !model.recordedBundleIDs.isEmpty {
                            Text("Recorded changes to restore")
                                .font(ThawType.heading)
                            Text(model.recordedBundleIDs.sorted().joined(separator: "\n"))
                                .font(ThawType.detail)
                                .textSelection(.enabled)
                        }
                        if model.candidates.isEmpty {
                            Text("No other apps are available for recovery. If an item is still missing, check its switch in System Settings → Menu Bar.")
                                .foregroundStyle(ThawInk.supporting)
                        } else {
                            Text("Other disabled apps")
                                .font(ThawType.heading)
                            Text("Thaw has no recovery record for these apps. Select only the ones you want to allow in the menu bar.")
                                .foregroundStyle(ThawInk.supporting)
                            ForEach(model.candidates) { candidate in
                                Toggle(isOn: selection(for: candidate.id)) {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: candidate.name)
                                        Text(verbatim: candidate.id)
                                            .font(ThawType.caption)
                                            .foregroundStyle(ThawInk.supporting)
                                    }
                                }
                            }
                        }
                    }

                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                        Text("Recovery records are kept until the visibility settings are verified. You can also enable the affected apps in System Settings.")
                            .foregroundStyle(ThawInk.supporting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Link("Open Menu Bar Settings", destination: URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                Spacer()
                Button("Quit Recovery") { NSApp.terminate(nil) }
                    .buttonStyle(.settingsGlass)
                    .disabled(model.isBusy)
                    .keyboardShortcut(.cancelAction)
                if model.successMessage == nil {
                    if model.supportsRecoveryBypass {
                        Button("Skip Recovery…") { confirmsBypass = true }
                            .buttonStyle(.settingsGlass)
                            .disabled(model.isBusy)
                    }
                    Button("Check Again") { Task { await model.load() } }
                        .buttonStyle(.settingsGlass)
                        .disabled(model.isBusy)
                    Button("Restore Visibility…") { confirmsRestore = true }
                        .buttonStyle(.thawProminent)
                        .disabled(!model.canRestore)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(ThawSpacing.gutter)
        .frame(minWidth: 620, minHeight: 480)
        .task { await model.load() }
        .confirmationDialog("Restore these visibility settings?", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("Restore Visibility") { Task { await model.restore() } }
            Button("Cancel", role: .cancel) { /* The dialog dismisses itself; cancelling needs no other work. */ }
        } message: {
            Text("Restore recorded states and enable the apps you selected. Your saved layout and positions will not be changed. Native hiding stays off.")
        }
        .alert("Skip recovery?", isPresented: $confirmsBypass) {
            Button("Skip Recovery") { model.bypassRecovery() }
            Button("Cancel", role: .cancel) {
                // Keep recovery active unless the user confirms.
            }
        } message: {
            Text("Thaw will keep the recovery records as backups and continue with Native hiding off. Some apps may remain hidden. Your saved layout and positions will not be changed.")
        }
        .alert("Set aside the unreadable record?", isPresented: $confirmsSetAside) {
            Button("Set Aside") { model.setAsideUnreadableRecords() }
            Button("Cancel", role: .cancel) {
                // Closing the alert is all Cancel does; the record stays where it is.
            }
        } message: {
            Text("Thaw keeps the file under a new name. Afterwards it can't tell which switched-off apps it hid, so you choose which ones to show and none are selected for you.")
        }
    }

    /// Why there is no app list yet, and the one way forward.
    @ViewBuilder
    private var unreadableRecord: some View {
        Text("Thaw can't read its record of the apps it hid")
            .font(ThawType.heading)
        Text("The file that lists which apps Thaw switched off in System Settings → Menu Bar is damaged or was written by a version this one can't read. Until it is set aside, Thaw can't show which apps it hid.")
            .foregroundStyle(ThawInk.supporting)
        Button("Set Aside Record…") { confirmsSetAside = true }
            .buttonStyle(.settingsGlass)
            .disabled(model.isBusy)
    }

    private var setAsideNotice: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.tight) {
            Text("The previous recovery records are kept at:")
            Text(verbatim: model.setAsideLocations.map(\.path).joined(separator: "\n"))
                .font(ThawType.detail)
                .textSelection(.enabled)
        }
    }

    private func selection(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedBundleIDs.contains(bundleID) },
            set: { selected in
                if selected {
                    model.selectedBundleIDs.insert(bundleID)
                } else {
                    model.selectedBundleIDs.remove(bundleID)
                }
            }
        )
    }
}
