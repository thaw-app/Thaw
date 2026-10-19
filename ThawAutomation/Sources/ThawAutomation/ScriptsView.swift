//
//  ScriptsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AutomationCore
import SwiftUI
import ThawModuleKit

/// The Scripts module's window: one pair of scripts for every switch, and a pair
/// for one profile.
struct ScriptsView: View {
    let store: HookStore
    let catalog: ProfileCatalog
    @State private var profiles: [ProfileSummary] = []
    @State private var selectedProfileID: UUID?
    @State private var isShowingEnvironment = false

    var body: some View {
        Form {
            Section("When any profile switches") {
                HookRow(label: "Before switching", hook: binding(\.globalPreHook))
                HookRow(label: "After switching", hook: binding(\.globalPostHook))
            }

            if !profiles.isEmpty {
                Section {
                    Picker("Profile", selection: $selectedProfileID) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    if let profileID = selectedProfileID {
                        HookRow(label: "Before switching", hook: profileBinding(profileID, \.preHook))
                        HookRow(label: "After switching", hook: profileBinding(profileID, \.postHook))
                    }
                } header: {
                    Text("Scripts for one profile")
                } footer: {
                    Text("They run between the two above, only when switching to this profile.")
                }
            }

            Section {
                Button("What scripts receive") { isShowingEnvironment = true }
                    .buttonStyle(.link)
                    .popover(isPresented: $isShowingEnvironment) { environmentHelp }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            profiles = catalog.profiles()
            selectedProfileID = selectedProfileID ?? profiles.first?.id
        }
    }

    private var environmentHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scripts get these environment variables:")
            Text(verbatim: "THAW_HOOK_PHASE\nTHAW_HOOK_SCOPE\nTHAW_PROFILE_ID\nTHAW_PROFILE_NAME\nTHAW_PREVIOUS_PROFILE_ID\nTHAW_PREVIOUS_PROFILE_NAME")
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text("Thaw doesn't wait for a script before it switches the layout.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, alignment: .leading)
        .padding()
    }

    private func binding(_ keyPath: WritableKeyPath<HookConfiguration, HookScript?>) -> Binding<HookScript?> {
        Binding(
            get: { store.configuration[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func profileBinding(_ id: UUID, _ keyPath: WritableKeyPath<ProfileAutomation, HookScript?>) -> Binding<HookScript?> {
        Binding(
            get: { store.configuration.profileHooks[id]?[keyPath: keyPath] },
            set: { newValue in
                store.update { configuration in
                    var automation = configuration.profileHooks[id] ?? ProfileAutomation()
                    automation[keyPath: keyPath] = newValue
                    configuration.profileHooks[id] = automation.isEmpty ? nil : automation
                }
            }
        )
    }
}
