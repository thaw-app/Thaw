//
//  HookRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawModuleKit
import UniformTypeIdentifiers

/// One script slot: choose a file, switch it off, set its timeout or remove it.
struct HookRow: View {
    let label: LocalizedStringKey
    @Binding var hook: HookScript?

    /// Timeouts offered in the menu; a stored value outside them is added.
    private static let timeouts: [Double] = [5, 10, 30, 60, 120, 300]

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Button(hook == nil ? "Choose…" : "Change…") { chooseScript() }

                if hook != nil {
                    Menu {
                        Toggle("Run this script", isOn: enabledBinding)
                            .toggleStyle(.automatic)
                        Picker("Timeout", selection: timeoutBinding) {
                            ForEach(timeoutChoices, id: \.self) { seconds in
                                Text("\(Int(seconds)) s").tag(seconds)
                            }
                        }
                        Divider()
                        Button("Remove Script", role: .destructive) { hook = nil }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("Script options")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let warning = validationWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var detail: String {
        let path = hook.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? String(localized: "None")
        guard let hook, !hook.isEnabled else { return path }
        return String(localized: "\(path), off")
    }

    private var timeoutChoices: [Double] {
        let current = hook?.timeoutSeconds ?? HookScript.defaultTimeout
        return Self.timeouts.contains(current) ? Self.timeouts : (Self.timeouts + [current]).sorted()
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { hook?.isEnabled ?? false },
            set: { newValue in
                guard var current = hook else { return }
                current.isEnabled = newValue
                hook = current
            }
        )
    }

    private var timeoutBinding: Binding<Double> {
        Binding(
            get: { hook?.timeoutSeconds ?? HookScript.defaultTimeout },
            set: { newValue in
                guard var current = hook else { return }
                current.timeoutSeconds = HookScript.clamp(newValue)
                hook = current
            }
        )
    }

    private var validationWarning: String? {
        guard let hook else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: hook.path) else {
            return String(localized: "File does not exist.")
        }
        if !hook.usesOSAScript, !fm.isExecutableFile(atPath: hook.path) {
            return String(localized: "Not executable. Run “chmod +x” on the file.")
        }
        return nil
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.shellScript,
            UTType.appleScript,
            UTType.executable,
            UTType.item,
        ]
        if let existingPath = hook?.path, !existingPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: existingPath).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if var current = hook {
            current.path = url.path
            hook = current
        } else {
            hook = HookScript(path: url.path)
        }
    }
}
