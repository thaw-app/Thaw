//
//  ToolsSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import ThawCapture
import ThawUI

struct ToolsSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: ToolsSettings

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
    @State private var tab = TroubleshootingTab.diagnostics

    var body: some View {
        ThawForm {
            // Diagnostics first, then tools that delete or reset something, with a full reset last.
            SettingsPaneTabs(
                selection: $tab,
                tabs: TroubleshootingTab.allCases,
                tabForSection: TroubleshootingTab.init(section:)
            )
            switch tab {
            case .diagnostics:
                diagnosticsTab
            case .repair:
                repairTab
            case .reset:
                resetTab
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
            Button("Cancel", role: .cancel) { /* The dialog dismisses itself; cancelling needs no other work. */ }
        } message: { action in
            Text(action.confirmationMessage)
        }
        .confirmationDialog("Open visibility recovery?", isPresented: $confirmsVisibilityRecovery, titleVisibility: .visible) {
            Button("Quit \(Constants.displayName) and Open Recovery") {
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
            Button("Cancel", role: .cancel) { /* The dialog dismisses itself; cancelling needs no other work. */ }
        } message: {
            Text("\(Constants.displayName) will quit normal mode so neither hiding mechanism can interfere. Your saved layout is kept. Native hiding will remain off after recovery.")
        }
        .errorAlert(failedAction?.errorTitle ?? "Couldn’t run tool", message: $errorMessage, role: .cancel)
    }

    // MARK: Tabs

    @ViewBuilder
    private var diagnosticsTab: some View {
        ThawSection("Diagnostics") {
            diagnosticLoggingToggle
            if settings.enableDiagnosticLogging {
                DiagnosticLogRotationRows(settings: settings)
                if let currentLogFileName {
                    LabeledContent("Current file") {
                        Text(currentLogFileName)
                            .foregroundStyle(ThawInk.supporting)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        DiagnosticFilesSection()
        // The move record is the log's live view, so it shows only while
        // the log is being written.
        if settings.enableDiagnosticLogging {
            MoveInspectorSection()
        }
    }

    /// These delete preferences or quit apps. The positions reset writes the
    /// backups listed below them, and its text points down to them.
    @ViewBuilder
    private var repairTab: some View {
        ThawSection("Repair") {
            toolRow(
                title: "Missing menu bar items",
                detail: "Restore app visibility without resetting your layout. Normal hiding stops while a separate recovery window is open.",
                buttonTitle: "Restore Missing Items…"
            ) {
                confirmsVisibilityRecovery = true
            }

            toolRow(
                title: "Menu bar",
                detail: "Restart the menu bar when it gets stuck, for example when it stays on top of full-screen apps. Your layout is kept, and \(Constants.displayName) relaunches afterward.",
                buttonTitle: "Restart Menu Bar…",
                statusFor: .restartMenuBar
            ) {
                pendingAction = .restartMenuBar
            }
            .settingsSearchAnchor("tools.restartMenuBar")

            toolRow(
                title: "macOS's saved layout",
                detail: "Delete the menu bar layout macOS keeps and restart the menu bar so macOS builds a new one. Use this when items won't come back to the menu bar after you move them. To move every item into one section instead, use Reset Layout on the Layout page. A backup is saved first; restore it from Layout backups below.",
                buttonTitle: "Rebuild Saved Layout…",
                role: .destructive,
                statusFor: .resetMenuBarLayoutPositions
            ) {
                pendingAction = .resetMenuBarLayoutPositions
            }
            .settingsSearchAnchor("tools.resetMenuBarLayoutPositions")

            toolRow(
                title: "Permissions",
                detail: "Clear Accessibility, Screen Recording and the files you picked for \(Constants.displayName), then quit so you can grant them again on next launch.",
                buttonTitle: "Reset Permissions…",
                role: .destructive,
                statusFor: .resetPermissions
            ) {
                pendingAction = .resetPermissions
            }
            .settingsSearchAnchor("tools.resetPermissions")

            toolRow(
                title: "Reduced mode",
                detail: "Run \(Constants.displayName) as one icon that hides whole apps, without reading the menu bar. Switch back from its menu.",
                buttonTitle: "Switch to Reduced Mode…",
                statusFor: .enterReducedMode
            ) {
                pendingAction = .enterReducedMode
            }
        }
        MenuBarLayoutBackupsSection(refreshToken: backupsRefreshToken)
    }

    private var resetTab: some View {
        ThawSection("Reset") {
            toolRow(
                title: "All settings",
                detail: "Restore every setting to its default and clear the apps allowed to change them, the welcome and What's New, dismissed tips and item pictures. Your menu bar layout and saved profiles stay. This can't be undone.",
                buttonTitle: "Reset \(Constants.displayName)…",
                role: .destructive,
                statusFor: .resetSettings
            ) {
                pendingAction = .resetSettings
            }
            .settingsSearchAnchor("tools.resetAllSettings")
        }
    }

    private var diagnosticLoggingToggle: some View {
        Toggle("Detailed logging", isOn: $settings.enableDiagnosticLogging)
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
            .settingsSearchAnchor("advanced.enableDiagnosticLogging")
    }

    private func toolRow(
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        buttonTitle: LocalizedStringResource,
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

        if action == .resetMenuBarLayoutPositions || action == .restartMenuBar {
            // Killing the host mid-move strands the move's events.
            await appState.itemManager.moveActivity.waitUntilIdle()
        }

        do {
            switch action {
            case .resetSettings:
                appState.settings.resetAllSettingsToDefaults()
                reportSuccess(String(localized: "Settings were reset to defaults."))
            case .resetMenuBarLayoutPositions:
                let backup = try await MaintenanceTools.resetMenuBarLayoutPositions()
                appState.itemManager.forgetStrandedRepairs()
                backupsRefreshToken += 1
                if let backup {
                    reportSuccess(
                        String(
                            localized: "macOS's saved layout was deleted. Backup saved as \(backup.url.lastPathComponent). Relaunching…"
                        )
                    )
                } else {
                    reportSuccess(String(localized: "macOS's saved layout was deleted. Relaunching…"))
                }
                // Access granted to the old layout table does not carry over to
                // the one the menu bar writes next, so relaunch once it exists.
                let table = MenuBarLayoutTableAccess.tableURL.path(percentEncoded: false)
                for _ in 0 ..< 60 where !FileManager.default.fileExists(atPath: table) {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                appState.restartSelf()
            case .restartMenuBar:
                try await MaintenanceTools.restartMenuBar()
                reportSuccess(String(localized: "The menu bar was restarted. Relaunching…"))
                // Thaw's hiding and positions sessions ended with the old host.
                appState.restartSelf()
            case .resetPermissions:
                try await MaintenanceTools.resetAppPermissions()
                reportSuccess(String(localized: "Permissions cleared. Quitting…"))
                ApplicationTermination.request()
            case .enterReducedMode:
                ReducedModeController.choose(keepingWithAccessibility: true)
                appState.restartSelf()
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
    case resetMenuBarLayoutPositions
    case restartMenuBar
    case resetPermissions
    case enterReducedMode

    var id: Self {
        self
    }

    var confirmationTitle: String {
        switch self {
        case .resetSettings: String(localized: "Reset all settings?")
        case .resetMenuBarLayoutPositions: String(localized: "Rebuild macOS's saved layout?")
        case .restartMenuBar: String(localized: "Restart the menu bar?")
        case .resetPermissions: String(localized: "Reset permissions?")
        case .enterReducedMode: String(localized: "Switch to Reduced mode?")
        }
    }

    var errorTitle: LocalizedStringResource {
        switch self {
        case .resetSettings: "Couldn’t reset settings"
        case .resetMenuBarLayoutPositions: "Couldn’t rebuild macOS's saved layout"
        case .restartMenuBar: "Couldn’t restart the menu bar"
        case .resetPermissions: "Couldn’t reset permissions"
        case .enterReducedMode: "Couldn’t switch to Reduced mode"
        }
    }

    var confirmationButtonTitle: LocalizedStringResource {
        switch self {
        case .resetSettings: "Reset"
        case .resetMenuBarLayoutPositions: "Rebuild Saved Layout"
        case .restartMenuBar: "Restart Menu Bar"
        case .resetPermissions: "Reset Permissions"
        case .enterReducedMode: "Switch"
        }
    }

    var confirmationMessage: LocalizedStringResource {
        switch self {
        case .resetSettings:
            "Every setting goes back to its default, and Thaw forgets the apps allowed to change settings, the welcome and What's New, dismissed tips and item pictures. Your menu bar layout and saved profiles stay. This can't be undone."
        case .resetMenuBarLayoutPositions:
            "Every menu bar item's saved position will be deleted and the menu bar will restart, so your whole arrangement is rebuilt from scratch. A backup is saved first, and Layout backups on this page can put it back. \(Constants.displayName) relaunches afterward."
        case .restartMenuBar:
            "The menu bar will disappear for a moment and come back. Your layout is kept. \(Constants.displayName) relaunches afterward."
        case .resetPermissions:
            "Accessibility and Screen Recording are cleared for \(Constants.displayName), and so is its access to the files you picked: the menu bar layout table and Control Center's app list. \(Constants.displayName) quits so you can grant them again on next launch."
        case .enterReducedMode:
            "\(ReducedModeOfferButton.consequence) \(Constants.displayName) relaunches as one icon; switch back from its menu."
        }
    }
}

nonisolated enum TroubleshootingTab: CaseIterable, ThawTab {
    case diagnostics
    case repair
    case reset

    /// The tab holding a search result's section.
    init?(section: String) {
        switch section {
        case "Diagnostics", "Files for a bug report": self = .diagnostics
        case "Repair": self = .repair
        case "Reset": self = .reset
        default: return nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .diagnostics: "Diagnostics"
        case .repair: "Repair"
        case .reset: "Reset"
        }
    }

    var systemImage: String {
        switch self {
        case .diagnostics: "stethoscope"
        case .repair: "wrench.and.screwdriver"
        case .reset: "arrow.counterclockwise"
        }
    }
}
