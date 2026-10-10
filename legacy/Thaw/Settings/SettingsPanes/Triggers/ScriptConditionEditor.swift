//
//  ScriptConditionEditor.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

// MARK: - ScriptConditionEditor

/// Editor for a script-result condition: a script path (with a file picker)
/// and an optional expected-output substring.
struct ScriptConditionEditor: View {
    @Binding var condition: TriggerCondition
    var focusedField: FocusState<String?>.Binding
    let focusID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CommitTextField(
                    title: "Script path",
                    prompt: "/path/to/script",
                    value: pathBinding,
                    focusedField: focusedField,
                    focusID: "scriptpath-\(focusID)"
                )
                Button("Choose…") { chooseScript() }
            }
            CommitTextField(
                title: "Expected output (optional)",
                prompt: "Leave empty to use exit code 0",
                value: expectedBinding,
                focusedField: focusedField,
                focusID: "scriptexp-\(focusID)"
            )
            Text("Runs your script about every 30 seconds. Reveals when it exits 0, or — if an expected output is set — when its output contains that text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pathBinding: Binding<String> {
        Binding(get: { condition.scriptValue?.path ?? "" }, set: { condition = condition.withScriptPath($0) })
    }

    private var expectedBinding: Binding<String> {
        Binding(get: { condition.scriptValue?.expectedOutput ?? "" }, set: { condition = condition.withScriptExpectedOutput($0) })
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            condition = condition.withScriptPath(url.path)
        }
    }
}
