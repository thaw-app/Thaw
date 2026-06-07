//
//  PermissionsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct PermissionsView<Manager: PermissionsManaging>: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var manager: Manager

    @State private var hasIceSettings = false
    @State private var showImportIceSettings = false
    @State private var isImportingIceSettings = false
    @State private var iceImportResult: (success: Bool, settingsImported: Int)?

    private let iceImporter = IceSettingsImporter()

    private var continueButtonText: LocalizedStringKey {
        if case .hasRequired = manager.permissionsState {
            "Continue in Limited Mode"
        } else {
            "Continue"
        }
    }

    private var continueButtonForegroundStyle: some ShapeStyle {
        switch manager.permissionsState {
        case .missing:
            AnyShapeStyle(.secondary)
        case .hasAll:
            AnyShapeStyle(.primary)
        case .hasRequired:
            AnyShapeStyle(.yellow)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            headerView

            if showImportIceSettings {
                iceImportBox
            }

            permissionsStack

            footerView
        }
        .padding(24)
        .frame(width: 760, height: 600)
        .onAppear {
            checkForIceSettings()
            showImportIceSettings = hasIceSettings && !Defaults.bool(forKey: .hasCompletedFirstLaunch)
        }
    }

    private var headerView: some View {
        VStack(spacing: 12) {
            Text("Enable Permissions")
                .font(.largeTitle.weight(.semibold))

            VStack(spacing: 4) {
                Text("Almost there! \(Constants.displayName) needs the permissions below to manage your menu bar.")
                Text("Your data stays on your Mac — nothing is ever collected or shared.")
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 500)
        }
    }

    private var permissionsStack: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(manager.allPermissions) { permission in
                PermissionCard(permission: permission)
            }
        }
    }

    private var footerView: some View {
        HStack(spacing: 12) {
            quitButton
            continueButton
        }
        .controlSize(.large)
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var continueButton: some View {
        Button {
            appState.completeFirstLaunchSetup()
        } label: {
            Text(continueButtonText)
                .frame(maxWidth: .infinity)
                .foregroundStyle(continueButtonForegroundStyle)
        }
        .buttonStyle(.borderedProminent)
        .disabled(manager.permissionsState == .missing)
    }

    private var iceImportBox: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 8) {
                Label("Import from Ice", systemImage: "square.and.arrow.down")
                    .font(.title3.weight(.semibold))

                Group {
                    if let result = iceImportResult {
                        if result.success {
                            Text("Imported \(result.settingsImported) settings successfully.")
                                .foregroundStyle(.green)
                        } else {
                            Text("Import failed. You can configure settings manually.")
                                .foregroundStyle(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("We found existing settings from Ice, the original app.")
                            Text("Icon positions can't be restored.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)

                if iceImportResult?.success == true {
                    Label("Imported", systemImage: "checkmark")
                        .foregroundStyle(.green)
                } else {
                    Button("Import Settings") {
                        importIceSettings()
                    }
                    .disabled(isImportingIceSettings)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkForIceSettings() {
        hasIceSettings = iceImporter.hasIceSettings()

        if !hasIceSettings {
            showImportIceSettings = false
        }
    }

    private func importIceSettings() {
        isImportingIceSettings = true

        Task { @MainActor in
            let result = iceImporter.importIceSettings()
            iceImportResult = result
            isImportingIceSettings = false

            if result.success {
                // Mark first launch as completed after successful import.
                //
                // Note: during a first-launch onboarding this also flips
                // ``OnboardingSheet/isFirstLaunchFlow`` to false mid-flow. That
                // stays correct — the permissions step is hosted in a window
                // that already rendered as the onboarding sheet (the host is
                // chosen once and isn't re-evaluated), and the final
                // ``AppState/completeFirstLaunchSetup()`` is idempotent.
                Defaults.set(true, forKey: .hasCompletedFirstLaunch)
                showImportIceSettings = true

                // Ensure section dividers are re-added after import by forcing a toggle
                // of the always-hidden section setting. This recreates control items
                // even when the setting was previously off.
                let currentlyEnabled = appState.settings.advanced.enableAlwaysHiddenSection
                appState.settings.advanced.enableAlwaysHiddenSection = !currentlyEnabled
                appState.settings.advanced.enableAlwaysHiddenSection = currentlyEnabled
            }
        }
    }
}

// MARK: - PermissionCard

/// A card describing a single permission, along with a button to grant it.
///
/// Shared by ``PermissionsView`` and the onboarding flow's permissions step,
/// so both present an identical, always-up-to-date view of permission state.
struct PermissionCard: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var permission: Permission
    @State var isRequestingPermission = false

    /// Whether granting should reopen/refocus the permissions window afterward.
    ///
    /// True in the standalone ``PermissionsView`` (the window *is* the host, so
    /// refocusing it is correct). False when the card is embedded in the
    /// onboarding tour's permissions preview — there the card lives inside the
    /// onboarding sheet, and popping a separate permissions window on top of it
    /// would be jarring, so granting just reactivates the app in place.
    var refocusesWindowAfterGrant = true

    var body: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(permission.title)
                        .font(.title2.weight(.semibold))
                } icon: {
                    Image(systemName: permission.iconName)
                        .font(.title2)
                        .foregroundStyle(permission.iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(permission.details, id: \.self) { detail in
                        Label {
                            Text(detail)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)

                if !permission.isRequired {
                    CalloutBox("\(Constants.displayName) can work in a limited mode without this permission.") {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                            .padding(-4)
                    }
                }

                Button {
                    guard !isRequestingPermission else {
                        return
                    }
                    isRequestingPermission = true
                    permission.performRequest()
                    Task { _ in
                        defer { isRequestingPermission = false }
                        await permission.waitForPermission()
                        appState.activate(withPolicy: .regular)
                        if refocusesWindowAfterGrant {
                            appState.openWindow(.permissions)
                        }
                    }
                } label: {
                    if permission.hasPermission {
                        Label("Permission Granted", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Grant Permission")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(permission.hasPermission ? .green : .accentColor)
                .allowsHitTesting(!permission.hasPermission)
                .disabled(isRequestingPermission)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private final class MockPermissionsManager: PermissionsManaging {
    @Published var permissionsState: AppPermissions.PermissionsState = .missing

    let allPermissions: [Permission] = [
        AccessibilityPermission(),
        ScreenRecordingPermission(),
    ]
}

#Preview {
    PermissionsView<MockPermissionsManager>()
        .environmentObject(AppState())
        .environmentObject(MockPermissionsManager())
}
