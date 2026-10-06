//
//  ToolsSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawCapture
import ThawUI

struct ToolsSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: AdvancedSettings

    @State private var currentLogFileName: String?
    @State private var pendingAction: MaintenanceToolAction?
    @State private var isBusy = false
    @State private var confirmsVisibilityRecovery = false
    @State private var statusMessage: String?
    /// The tool whose row shows statusMessage, so a result reads beside
    /// the button that produced it rather than at the foot of the page.
    @State private var statusAction: MaintenanceToolAction?
    @State private var errorMessage: String?
    @State private var failedAction: MaintenanceToolAction?
    // The browser below reloads on this rather than watching the folder,
    // because a reset is the only thing on this pane that writes a backup.
    @State private var backupsRefreshToken = 0

    var body: some View {
        ThawForm {
            // Everyday utilities first, then the ones that delete or reset
            // something, with a reset of everything last. What the app
            // observes lives on the Privacy pane, beside the permissions that
            // allow it.
            ThawSection("Onboarding") {
                toolRow(
                    title: "Welcome screens",
                    detail: "Show the welcome, access, and setup screens again.",
                    buttonTitle: "Show Again"
                ) {
                    appState.replayOnboarding()
                }
            }

            // Non-destructive, but a level down from daily use.
            ThawSection("Diagnostics") {
                diagnosticLogging
            }
            // The move record is the log's live view, so it shows only while
            // the log is being written.
            if settings.enableDiagnosticLogging {
                MoveInspectorSection()
            }

            // Above Troubleshooting because the positions reset there writes
            // the backups this lists, and its copy points up to it.
            MenuBarLayoutBackupsSection(refreshToken: backupsRefreshToken)

            // These delete preferences, clear the cache, or quit apps.
            ThawSection("Troubleshooting") {
                toolRow(
                    title: "Missing menu bar items",
                    detail: "Restore app visibility without resetting your layout. Normal hiding stops while a separate recovery window is open.",
                    buttonTitle: "Restore Missing Items…"
                ) {
                    confirmsVisibilityRecovery = true
                }

                toolRow(
                    title: "Control Center preferences",
                    detail: "Quit Control Center and delete its preference files so the state of Apple's menu bar items can rebuild.",
                    buttonTitle: "Reset Control Center…",
                    role: .destructive,
                    statusFor: .resetControlCenter
                ) {
                    pendingAction = .resetControlCenter
                }

                // Saved positions live in the menu bar's own domain, not
                // Control Center's, so the row above does not clear them and
                // this one is a separate reset rather than a duplicate.
                toolRow(
                    title: "Saved item positions",
                    detail: "Delete macOS's saved menu bar layout and restart the menu bar so it rebuilds from scratch. Use this when items won't come back to the menu bar after you move them. A backup is saved first; restore it from Layout backups above.",
                    buttonTitle: "Reset Positions…",
                    role: .destructive,
                    statusFor: .resetMenuBarLayoutPositions
                ) {
                    pendingAction = .resetMenuBarLayoutPositions
                }

                toolRow(
                    title: "Cache",
                    detail: "Delete \(Constants.displayName)'s cache folder, then quit the app.",
                    buttonTitle: "Quit and Clear Cache…",
                    role: .destructive,
                    statusFor: .quitAndClearCache
                ) {
                    pendingAction = .quitAndClearCache
                }

                toolRow(
                    title: "Permissions",
                    detail: "Clear Accessibility and Screen Recording decisions for \(Constants.displayName), then quit so you can grant them again on next launch.",
                    buttonTitle: "Reset Permissions…",
                    role: .destructive,
                    statusFor: .resetPermissions
                ) {
                    pendingAction = .resetPermissions
                }
            }

            ThawSection("Reset") {
                toolRow(
                    title: "All settings",
                    detail: "Restore \(Constants.displayName) settings to their defaults. Saved profiles, allowed apps, and user data are not deleted. This cannot be undone.",
                    buttonTitle: "Reset \(Constants.displayName)…",
                    role: .destructive,
                    statusFor: .resetSettings
                ) {
                    pendingAction = .resetSettings
                }
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
            item: $pendingAction,
            titleVisibility: .visible
        ) { action in
            Button(action.confirmationButtonTitle, role: .destructive) {
                Task { await perform(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.confirmationMessage)
        }
        .confirmationDialog("Open visibility recovery?", isPresented: $confirmsVisibilityRecovery, titleVisibility: .visible) {
            Button("Quit Thaw and Open Recovery") {
                Task {
                    isBusy = true
                    defer { isBusy = false }
                    do {
                        try await NativeVisibilityRecoveryLaunch.openRecovery()
                    } catch {
                        failedAction = nil
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Thaw will quit normal mode so neither hiding mechanism can interfere. Your saved layout is kept. Native hiding will remain off after recovery.")
        }
        .errorAlert(failedAction?.errorTitle ?? "Couldn’t run tool", message: $errorMessage, role: .cancel)
    }

    private var diagnosticLogging: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            Toggle(
                "Detailed logging",
                isOn: $settings.enableDiagnosticLogging
            )
            .annotation {
                Text(
                    """
                    Writes a detailed log to ~/Library/Logs/Thaw/ for troubleshooting, \
                    and lists recent item moves below. Turn it off when you are done \
                    to avoid needless disk writes. Short crash reports are saved even \
                    when this is off.
                    """
                )
            }

            HStack(spacing: ThawSpacing.inset) {
                Button("Show Log Files in Finder") {
                    NSWorkspace.shared.open(DiagnosticLogger.shared.logDirectory)
                }
                .buttonStyle(.settingsGlass)

                if let currentLogFileName {
                    Text(currentLogFileName)
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                }
            }
        }
    }

    private func toolRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        buttonTitle: LocalizedStringKey,
        role: ButtonRole? = nil,
        statusFor tool: MaintenanceToolAction? = nil,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            HStack(alignment: .top, spacing: ThawSpacing.gutter) {
                Text(title)
                    .annotation(detail, spacing: ThawSpacing.tight, font: ThawType.footnote, foregroundStyle: ThawInk.supporting)
                Button(buttonTitle, role: role, action: action)
                    .buttonStyle(.settingsGlass)
            }
            if let tool, statusAction == tool, let statusMessage {
                Text(statusMessage)
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @MainActor
    private func perform(_ action: MaintenanceToolAction) async {
        pendingAction = nil
        isBusy = true
        statusMessage = nil
        statusAction = action
        defer { isBusy = false }

        if action == .resetControlCenter || action == .resetMenuBarLayoutPositions {
            // Killing the host mid-move strands the move's events.
            await appState.itemManager.moveActivity.waitUntilIdle()
        }

        do {
            switch action {
            case .resetSettings:
                appState.settings.resetAllSettingsToDefaults()
                reportSuccess(String(localized: "Settings were reset to defaults."))
            case .resetControlCenter:
                try await MaintenanceTools.resetControlCenterPreferences()
                reportSuccess(String(localized: "Control Center preferences were reset."))
            case .resetMenuBarLayoutPositions:
                let backup = try await MaintenanceTools.resetMenuBarLayoutPositions()
                backupsRefreshToken += 1
                if let backup {
                    reportSuccess(
                        String(
                            localized: "Saved item positions were reset. Backup saved as \(backup.url.lastPathComponent)."
                        )
                    )
                } else {
                    reportSuccess(String(localized: "Saved item positions were reset."))
                }
            case .quitAndClearCache:
                await appState.imageCache.suspendDiskPersistenceForReset()
                do {
                    try MaintenanceTools.clearAppCache()
                } catch {
                    appState.imageCache.resumeDiskPersistenceAfterFailedReset()
                    throw error
                }
                reportSuccess(String(localized: "Cache cleared. Quitting…"))
                ApplicationTermination.request()
            case .resetPermissions:
                try await MaintenanceTools.resetAppPermissions()
                reportSuccess(String(localized: "Permissions cleared. Quitting…"))
                ApplicationTermination.request()
            }
        } catch {
            failedAction = action
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
        case .resetMenuBarLayoutPositions: String(localized: "Reset saved item positions?")
        case .quitAndClearCache: String(localized: "Quit and clear cache?")
        case .resetPermissions: String(localized: "Reset permissions?")
        }
    }

    var errorTitle: LocalizedStringKey {
        switch self {
        case .resetSettings: "Couldn’t reset settings"
        case .resetControlCenter: "Couldn’t reset Control Center"
        case .resetMenuBarLayoutPositions: "Couldn’t reset saved item positions"
        case .quitAndClearCache: "Couldn’t clear the cache"
        case .resetPermissions: "Couldn’t reset permissions"
        }
    }

    var confirmationButtonTitle: LocalizedStringKey {
        switch self {
        case .resetSettings: "Reset"
        case .resetControlCenter: "Reset Control Center"
        case .resetMenuBarLayoutPositions: "Reset Positions"
        case .quitAndClearCache: "Quit and Clear Cache"
        case .resetPermissions: "Reset Permissions"
        }
    }

    var confirmationMessage: LocalizedStringKey {
        switch self {
        case .resetSettings:
            "This will reset app settings to their default values. Saved profiles, allowed apps, and user data will not be deleted. This action cannot be undone."
        case .resetControlCenter:
            "Control Center will quit and its preference files will be deleted. macOS usually relaunches it automatically."
        case .resetMenuBarLayoutPositions:
            "Every menu bar item's saved position will be deleted and the menu bar will restart, so your whole arrangement is rebuilt from scratch. A backup is saved first, and Layout backups on this page can put it back."
        case .quitAndClearCache:
            "\(Constants.displayName) will delete its cache folder and quit. Launch the app again afterward."
        case .resetPermissions:
            "Accessibility and Screen Recording permissions will be cleared for \(Constants.displayName). The app will quit so you can grant them again on next launch."
        }
    }
}
