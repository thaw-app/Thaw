//
//  TriggersSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

struct TriggersSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var manager: AppRunningTriggersManager
    @State private var draft = AppRunningTrigger()
    @State private var isEditing = false
    @State private var pendingRemoval: AppRunningTrigger?
    @State private var isResetting = false

    var body: some View {
        ThawForm {
            ThawSection("App is running") {
                Text("Show selected menu bar items while an app runs, even in the background. When it quits, the items follow their saved layout again.")
                Text("macOS may also show other menu bar items from the same app.")
                    .font(ThawType.detail)
                    .foregroundStyle(.secondary)
                Button("Add Trigger") {
                    draft = AppRunningTrigger()
                    isEditing = true
                }
                .disabled(!manager.canEdit)
            }

            if !manager.canEdit {
                ThawSection("Saved triggers unavailable") {
                    Text("Saved triggers could not be read and have not been changed. Resetting removes only these trigger rules.")
                    Button("Reset Triggers", role: .destructive) { isResetting = true }
                }
            } else if manager.rules.isEmpty {
                ThawSection {
                    Text("No triggers yet")
                        .font(ThawType.heading)
                    Text("Add a trigger to choose an app and the items it should reveal.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(manager.rules) { rule in
                    ThawSection {
                        Toggle(isOn: Binding(
                            get: { rule.isEnabled },
                            set: { manager.setEnabled($0, id: rule.id) }
                        )) {
                            Text("While \(rule.appName) is running")
                        }
                        Text(rule.targets.map(\.name).formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                        Text(status(for: rule))
                            .font(ThawType.detail)
                        HStack {
                            Button("Edit") {
                                draft = rule
                                isEditing = true
                            }
                            .accessibilityLabel("Edit trigger for \(rule.appName)")
                            Button("Remove", role: .destructive) { pendingRemoval = rule }
                                .accessibilityLabel("Remove trigger for \(rule.appName)")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            AppRunningTriggerEditor(draft: $draft, availableTargets: availableTargets) {
                manager.save(draft)
            }
        }
        .confirmationDialog(
            "Remove this trigger?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: {
                    if !$0 {
                        pendingRemoval = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Trigger", role: .destructive) {
                if let rule = pendingRemoval {
                    manager.remove(id: rule.id)
                }
                pendingRemoval = nil
            }
        } message: {
            Text("Its items will follow the saved layout unless another trigger still reveals them.")
        }
        .confirmationDialog("Reset all triggers?", isPresented: $isResetting, titleVisibility: .visible) {
            Button("Reset Triggers", role: .destructive) { manager.reset() }
        }
        .errorAlert("Triggers", message: $manager.errorMessage)
    }

    private var availableTargets: [AppRunningTrigger.Target] {
        var seen = Set<String>()
        return appState.itemManager.managedItems.compactMap { item in
            let id = item.tag.tagIdentifier
            guard !item.isControlItem, !item.isSystemClone, !item.isNativeOverflowControl,
                  !item.isNonConcealableSystemItem, seen.insert(id).inserted
            else { return nil }
            return AppRunningTrigger.Target(id: id, name: MenuBarItemDisplayName.displayName(for: item))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func status(for rule: AppRunningTrigger) -> String {
        if !rule.isEnabled {
            return String(localized: "Disabled")
        }
        return rule.matches(runningBundleIDs: manager.runningBundleIDs)
            ? String(localized: "App is running")
            : String(localized: "Waiting for app to launch")
    }
}

private struct AppRunningTriggerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: AppRunningTrigger
    let availableTargets: [AppRunningTrigger.Target]
    let save: () -> Bool
    @State private var isChoosingApp = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            Text("App is running")
                .font(ThawType.display)
            ThawForm {
                ThawSection("When this app runs") {
                    if !draft.appBundleID.isEmpty {
                        Text(draft.appName)
                        Text(draft.appBundleID)
                            .font(ThawType.detail)
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose App") { isChoosingApp = true }
                }
                ThawSection("Show these menu bar items") {
                    if targets.isEmpty {
                        Text("Launch an app with a menu bar item to make it available here.")
                    }
                    ForEach(targets) { target in
                        Toggle(isOn: Binding(
                            get: { draft.targets.contains { $0.id == target.id } },
                            set: { selected in
                                draft.targets.removeAll { $0.id == target.id }
                                if selected {
                                    draft.targets.append(target)
                                }
                            }
                        )) {
                            Text(target.name)
                            if !availableTargets.contains(where: { $0.id == target.id }) {
                                Text("Not currently in the menu bar")
                                    .font(ThawType.detail)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Trigger") {
                    if save() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
        }
        .padding(ThawSpacing.section)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 540)
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.application]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
                    errorMessage = String(localized: "Choose an application with a bundle identifier.")
                    return
                }
                draft.appBundleID = bundleID
                draft.appName = FileManager.default.displayName(atPath: url.path)
            } catch {
                errorMessage = String(localized: "The app could not be selected. Try again.")
            }
        }
        .errorAlert("Choose App", message: $errorMessage)
    }

    private var targets: [AppRunningTrigger.Target] {
        let present = Set(availableTargets.map(\.id))
        return availableTargets + draft.targets.filter { !present.contains($0.id) }
    }
}
