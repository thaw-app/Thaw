//
//  ToolsSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct ToolsSettingsPane: View {
    @Environment(AppState.self) private var appState: AppState
    @Bindable var settings: AdvancedSettings

    @State private var currentLogFileName: String?
    @State private var pendingAction: MaintenanceToolAction?
    @State private var languageOverrideChanged = false
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        IceForm {
            SettingsWarningPill(
                title: "Safe vs maintenance tools",
                message: "Diagnostics and Onboarding are non-destructive. Reset and Troubleshooting can delete preferences, clear the cache, or quit apps.",
                systemImage: "info.circle.fill",
                tint: .blue
            )
            // A bare child of the grouped Form still gets a row card; clear
            // it so the pill renders "alone" like section-footer pills.
            .listRowBackground(Color.clear)

            IceSection("Diagnostics") {
                diagnosticLogging
            }
            IceSection("Onboarding") {
                toolRow(
                    title: "Replay onboarding",
                    detail: "Review the feature tour and permission setup again.",
                    buttonTitle: "Replay Onboarding"
                ) {
                    appState.isOnboardingPresented = true
                }
            }
            IceSection("Language") {
                languageRow
            }
            IceSection("Reset") {
                toolRow(
                    title: "Reset all settings",
                    detail: "Restore \(Constants.displayName) preferences to their defaults. Saved profiles and user data are not deleted. This cannot be undone.",
                    buttonTitle: "Reset \(Constants.displayName)",
                    role: .destructive
                ) {
                    pendingAction = .resetSettings
                }
            }
            IceSection("Troubleshooting") {
                toolRow(
                    title: "Reset Control Center preferences",
                    detail: "Quit Control Center and delete its preference files so system menu bar item state can rebuild.",
                    buttonTitle: "Reset Control Center"
                ) {
                    pendingAction = .resetControlCenter
                }

                toolRow(
                    title: "Reset menu bar layout positions",
                    detail: "Quit the menu bar host and delete its saved item positions, so the menu bar arrangement rebuilds from scratch. Use this when items refuse to return to the menu bar after rearranging.",
                    buttonTitle: "Reset Layout Positions",
                    role: .destructive
                ) {
                    pendingAction = .resetMenuBarLayoutPositions
                }

                toolRow(
                    title: "Quit and clear cache",
                    detail: "Delete \(Constants.displayName)'s cache folder, then quit the app.",
                    buttonTitle: "Quit & Clear Cache",
                    role: .destructive
                ) {
                    pendingAction = .quitAndClearCache
                }

                toolRow(
                    title: "Reset permissions",
                    detail: "Clear Accessibility and Screen Recording decisions for \(Constants.displayName), then quit so you can re-grant them on next launch.",
                    buttonTitle: "Reset Permissions",
                    role: .destructive
                ) {
                    pendingAction = .resetPermissions
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(isBusy)
        .task(id: settings.enableDiagnosticLogging) {
            try? await Task.sleep(for: .milliseconds(50))
            currentLogFileName = (
                DiagnosticLogger.shared.currentLogFile
                    ?? DiagnosticLogger.shared.latestLogFile
            )?.lastPathComponent
        }
        .confirmationDialog(
            pendingAction?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: {
                    if !$0 {
                        pendingAction = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmationButtonTitle, role: .destructive) {
                Task { await perform(action) }
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: { action in
            Text(action.confirmationMessage)
        }
        .alert(
            "Couldn't run tool",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var diagnosticLogging: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Enable diagnostic logging",
                isOn: $settings.enableDiagnosticLogging
            )
            .annotation {
                Text(
                    """
                    Writes detailed debug logs to a file for troubleshooting. \
                    Log files are saved to ~/Library/Logs/Thaw/. \
                    Disable when not needed to avoid unnecessary disk writes.
                    """
                )
            }

            HStack(spacing: 12) {
                if settings.enableDiagnosticLogging || DiagnosticLogger.shared.hasLogFiles {
                    Button("Show Log Files in Finder") {
                        NSWorkspace.shared.open(DiagnosticLogger.shared.logDirectory)
                    }
                }

                if let currentLogFileName {
                    Text(currentLogFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Sentinel for following the system language (no override).
    private static let systemLanguageTag = "system"

    /// The app's per-app language override, via the standard `AppleLanguages`
    /// mechanism. Not a `Defaults.Key` — the key name is owned by macOS.
    private var currentLanguageOverride: String {
        (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
            ?? Self.systemLanguageTag
    }

    @ViewBuilder
    private var languageRow: some View {
        let localizations = Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted { lhs, rhs in
                displayName(forLanguage: lhs) < displayName(forLanguage: rhs)
            }

        IcePicker(
            "App language",
            selection: Binding(
                get: { currentLanguageOverride },
                set: { newValue in
                    if newValue == Self.systemLanguageTag {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                    languageOverrideChanged = true
                }
            )
        ) {
            Text("System Default").tag(Self.systemLanguageTag)
            ForEach(localizations, id: \.self) { code in
                Text(displayName(forLanguage: code)).tag(code)
            }
        }
        .annotation("Use \(Constants.displayName) in a different language than the system. Takes effect after a relaunch.")

        if languageOverrideChanged {
            HStack {
                Text("The language change applies after \(Constants.displayName) relaunches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Relaunch Now") {
                    relaunchApp()
                }
            }
        }
    }

    /// The language's own name for itself (endonym), falling back to the code.
    private func displayName(forLanguage code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.localizedCapitalized ?? code
    }

    private func relaunchApp() {
        // Terminate first, reopen after: launching a second instance while
        // this one is still alive races teardown and can leave multiple
        // copies running. The detached shell outlives the app, waits for
        // this PID to exit, and only then opens the bundle again.
        // Foundation Process rather than the Subprocess package on purpose —
        // Subprocess ties the child's lifetime to the awaiting task, which
        // dies with the app before the relaunch could fire.
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"\(bundlePath)\"",
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func toolRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        buttonTitle: LocalizedStringKey,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(buttonTitle, role: role, action: action)
                .buttonStyle(.settingsGlass)
        }
    }

    @MainActor
    private func perform(_ action: MaintenanceToolAction) async {
        pendingAction = nil
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }

        do {
            switch action {
            case .resetSettings:
                appState.settings.resetAllSettingsToDefaults()
                reportSuccess(String(localized: "Settings were reset to defaults."))
            case .resetControlCenter:
                try await MaintenanceTools.resetControlCenterPreferences()
                reportSuccess(String(localized: "Control Center preferences were reset."))
            case .resetMenuBarLayoutPositions:
                try await MaintenanceTools.resetMenuBarLayoutPositions()
                reportSuccess(String(localized: "Menu bar layout positions were reset."))
            case .quitAndClearCache:
                try MaintenanceTools.clearAppCache()
                reportSuccess(String(localized: "Cache cleared. Quitting…"))
                ApplicationTermination.request()
            case .resetPermissions:
                try await MaintenanceTools.resetAppPermissions()
                reportSuccess(String(localized: "Permissions cleared. Quitting…"))
                ApplicationTermination.request()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reportSuccess(_ message: String) {
        statusMessage = message
        AccessibilityAnnouncements.post(message)
    }
}

private enum MaintenanceToolAction: Identifiable {
    case resetSettings
    case resetControlCenter
    case resetMenuBarLayoutPositions
    case quitAndClearCache
    case resetPermissions

    var id: Self {
        self
    }

    var confirmationTitle: String {
        switch self {
        case .resetSettings: String(localized: "Reset all settings?")
        case .resetControlCenter: String(localized: "Reset Control Center preferences?")
        case .resetMenuBarLayoutPositions: String(localized: "Reset menu bar layout positions?")
        case .quitAndClearCache: String(localized: "Quit and clear cache?")
        case .resetPermissions: String(localized: "Reset permissions?")
        }
    }

    var confirmationButtonTitle: LocalizedStringKey {
        switch self {
        case .resetSettings: "Reset"
        case .resetControlCenter: "Reset Control Center"
        case .resetMenuBarLayoutPositions: "Reset Layout Positions"
        case .quitAndClearCache: "Quit & Clear Cache"
        case .resetPermissions: "Reset Permissions"
        }
    }

    var confirmationMessage: LocalizedStringKey {
        switch self {
        case .resetSettings:
            "This will reset app preferences to their default values. Saved profiles and user data will not be deleted. This action cannot be undone."
        case .resetControlCenter:
            "Control Center will quit and its preference files will be deleted. macOS usually relaunches it automatically."
        case .resetMenuBarLayoutPositions:
            "Every saved status-item position will be deleted and the menu bar host will quit, so your whole menu bar arrangement is rebuilt from scratch."
        case .quitAndClearCache:
            "\(Constants.displayName) will delete its cache folder and quit. Launch the app again afterward."
        case .resetPermissions:
            "Accessibility and Screen Recording permissions will be cleared for \(Constants.displayName). The app will quit so you can grant them again on next launch."
        }
    }
}
