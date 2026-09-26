//
//  CommitTextField.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - CommitTextField

/// Edits a local draft and commits only on Enter or focus loss, since each commit
/// re-renders the settings window and steals focus. The enclosing pane owns focus
/// so clicking away dismisses the field.
struct CommitTextField: View {
    let title: String
    let prompt: String?
    @Binding var value: String
    var focusedField: FocusState<String?>.Binding
    let focusID: String

    @State private var draft: String = ""

    var body: some View {
        TextField(title, text: $draft, prompt: prompt.map { Text(verbatim: $0) })
            .textFieldStyle(.roundedBorder)
            .focused(focusedField, equals: focusID)
            .onAppear { draft = value }
            .onChange(of: value) { _, newValue in
                if focusedField.wrappedValue != focusID {
                    draft = newValue
                }
            }
            .onChange(of: focusedField.wrappedValue) { _, newValue in
                if newValue != focusID {
                    commit()
                }
            }
            .onSubmit {
                commit()
                focusedField.wrappedValue = nil
            }
            .onDisappear {
                // Switching panes tears the field down with focus still on it,
                // so neither of the commits above ever runs and the draft would
                // be lost.
                commit()
            }
    }

    private func commit() {
        if draft != value {
            value = draft
        }
    }
}
