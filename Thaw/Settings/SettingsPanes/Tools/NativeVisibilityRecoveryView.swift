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
                    } else if model.hasLoaded {
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
                    .disabled(model.isBusy)
                    .keyboardShortcut(.cancelAction)
                if model.successMessage == nil {
                    Button("Check Again") { Task { await model.load() } }
                        .disabled(model.isBusy)
                    Button("Restore Visibility…") { confirmsRestore = true }
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
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore recorded states and enable the apps you selected. Your saved layout and positions will not be changed. Native hiding stays off.")
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
