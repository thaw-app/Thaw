//
//  TriggersView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import TriggersCore
import UniformTypeIdentifiers

/// The Thaw Triggers window.
struct TriggersView: View {
    @Bindable var manager: AppRunningTriggersManager
    let itemSource: ThawItemSource
    @State private var draft = AppRunningTrigger()
    @State private var isEditing = false
    @State private var pendingRemoval: AppRunningTrigger?
    @State private var isResetting = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Add Trigger") {
                        draft = AppRunningTrigger()
                        isEditing = true
                    }
                    .disabled(!manager.canEdit)
                } label: {
                    Text("Show chosen items")
                    Text("They show while the app runs, even in the background, and go back to their place when it quits.")
                }
                .help("macOS may also show other menu bar items from the same app.")
            } header: {
                Text("When an app runs")
            }

            if !manager.canEdit {
                Section("Saved triggers unavailable") {
                    Text("Saved triggers could not be read and have not been changed. Resetting removes your triggers and nothing else.")
                    Button("Reset Triggers", role: .destructive) { isResetting = true }
                }
            } else {
                ForEach(manager.rules) { rule in
                    Section {
                        ruleRows(rule)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 360)
        .sheet(isPresented: $isEditing) {
            TriggerEditor(draft: $draft, itemSource: itemSource) {
                manager.save(draft)
            }
        }
        .confirmationDialog(
            "Remove this trigger?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: {
                if !$0 {
                    pendingRemoval = nil
                }
            }),
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
        .alert("Triggers", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: {
                if !$0 {
                    manager.errorMessage = nil
                }
            }
        )) {} message: {
            Text(manager.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func ruleRows(_ rule: AppRunningTrigger) -> some View {
        Toggle(isOn: Binding(get: { rule.isEnabled }, set: { manager.setEnabled($0, id: rule.id) })) {
            Text("While \(rule.appName) is running")
        }
        Text(rule.targets.map(\.name).formatted(.list(type: .and)))
            .foregroundStyle(.secondary)
        Text(status(for: rule))
            .font(.caption)
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

    private func status(for rule: AppRunningTrigger) -> String {
        if !rule.isEnabled {
            return String(localized: "Disabled")
        }
        return rule.matches(runningBundleIDs: manager.runningBundleIDs)
            ? String(localized: "App is running")
            : String(localized: "Waiting for app to launch")
    }
}

/// Chooses the app and the items one trigger shows.
private struct TriggerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: AppRunningTrigger
    let itemSource: ThawItemSource
    let save: () -> Bool
    @State private var isChoosingApp = false
    @State private var errorMessage: String?

    private var availableTargets: [AppRunningTrigger.Target] {
        var seen = Set<String>()
        return itemSource.items
            .filter { seen.insert($0.id).inserted }
            .map { AppRunningTrigger.Target(id: $0.id, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var targets: [AppRunningTrigger.Target] {
        let present = Set(availableTargets.map(\.id))
        return availableTargets + draft.targets.filter { !present.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trigger")
                .font(.title2.weight(.semibold))
            Form {
                Section("When this app runs") {
                    if !draft.appBundleID.isEmpty {
                        Text(draft.appName)
                        Text(draft.appBundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose App") { isChoosingApp = true }
                }
                Section {
                    if let problem = itemSource.problem {
                        Text(problem)
                            .foregroundStyle(.orange)
                    } else if targets.isEmpty {
                        Text("Launch an app with a menu bar item to make it available here.")
                    }
                    ForEach(targets) { target in
                        targetToggle(target)
                    }
                } header: {
                    HStack {
                        Text("Show these menu bar items")
                        Spacer()
                        Button("Refresh") { itemSource.refresh() }
                            .buttonStyle(.link)
                    }
                }
            }
            .formStyle(.grouped)
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
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 540)
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.application]) { result in
            chooseApp(result)
        }
        .alert("Choose App", isPresented: Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })) {} message: {
            Text(errorMessage ?? "")
        }
    }

    private func targetToggle(_ target: AppRunningTrigger.Target) -> some View {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseApp(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
                errorMessage = String(localized: "Choose an application with a bundle identifier.")
                return
            }
            draft.appBundleID = bundleID
            draft.appName = FileManager.default.displayName(atPath: url.path)
        } catch {
            errorMessage = String(localized: "The app could not be selected. Try again.")
        }
    }
}
