//
//  PermissionsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The standalone permissions screen: shows a card per required permission,
/// an optional Ice settings import prompt, and Quit/Continue actions that
/// gate first-launch setup.
struct PermissionsView<Manager: PermissionsManaging>: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var manager: Manager

    @State private var hasIceSettings = false
    @State private var showImportIceSettings = false
    @State private var isImportingIceSettings = false
    @State private var iceImportResult: (success: Bool, settingsImported: Int)?

    private let iceImporter = IceSettingsImporter()

    /// The continue button's label — calls out limited mode when only the
    /// required (not all) permissions have been granted.
    private var continueButtonText: LocalizedStringKey {
        if case .hasRequired = manager.permissionsState {
            "Continue in Limited Mode"
        } else {
            "Continue"
        }
    }

    /// The continue button's foreground style, reflecting how complete the
    /// granted permissions are.
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

            VStack(spacing: 16) {
                limitedModeFootnote
                footerView
            }
        }
        .padding(24)
        .frame(width: 760, height: 600)
        .onAppear {
            checkForIceSettings()
            showImportIceSettings = hasIceSettings && !Defaults.bool(forKey: .hasCompletedFirstLaunch)
        }
    }

    /// The title and reassurance copy shown above the permission cards.
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

    /// A horizontal row of cards, one per permission the manager exposes.
    private var permissionsStack: some View {
        HStack(spacing: 16) {
            ForEach(manager.allPermissions) { permission in
                PermissionCard(permission: permission)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Reassures the user that Screen Recording is optional and the app can
    /// still run, just with reduced functionality, without it.
    private var limitedModeFootnote: some View {
        Label {
            Text("\(Constants.displayName) can work in a limited mode without Screen Recording.")
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.green)
        }
        .font(.subheadline)
    }

    /// The Quit / Continue action row beneath the permission cards.
    private var footerView: some View {
        HStack(spacing: 12) {
            quitButton
            continueButton
        }
        .controlSize(.large)
    }

    /// Terminates the app outright — the only sound option when the user
    /// won't proceed through the mandatory first-launch permissions step.
    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            Text("Quit")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// Completes first-launch setup with whatever permissions are currently
    /// granted. Disabled until at least the required permissions are in place.
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

    /// A prompt offering to import settings from a detected Ice install,
    /// shown only on first launch when such settings are present.
    private var iceImportBox: some View {
        IceSection {
            HStack(alignment: .center) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Ice")
                            .font(.headline)
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
                                Text("Found existing settings. Icon positions can't be restored.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                }

                Spacer()

                if iceImportResult?.success == true {
                    Label("Imported", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.medium))
                } else {
                    Button("Import Settings") {
                        importIceSettings()
                    }
                    .disabled(isImportingIceSettings)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
        }
    }

    /// Refreshes whether an importable Ice install was detected, hiding the
    /// import prompt if it's no longer applicable.
    private func checkForIceSettings() {
        hasIceSettings = iceImporter.hasIceSettings()

        if !hasIceSettings {
            showImportIceSettings = false
        }
    }

    /// Imports settings from the detected Ice install, surfacing the result
    /// and nudging the always-hidden section setting to force it to refresh.
    private func importIceSettings() {
        isImportingIceSettings = true

        Task { @MainActor in
            let result = iceImporter.importIceSettings()
            iceImportResult = result
            isImportingIceSettings = false

            if result.success {
                Defaults.set(true, forKey: .hasCompletedFirstLaunch)
                showImportIceSettings = true

                let currentlyEnabled = appState.settings.advanced.enableAlwaysHiddenSection
                appState.settings.advanced.enableAlwaysHiddenSection = !currentlyEnabled
                appState.settings.advanced.enableAlwaysHiddenSection = currentlyEnabled
            }
        }
    }
}

// MARK: - PermissionCard

/// A card describing a single permission — its icon, title, details, and a
/// button to request it (or a confirmation once it's been granted).
struct PermissionCard: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var permission: Permission
    @State var isRequestingPermission = false

    /// Whether granting the permission should bring the permissions window
    /// back to the front. Disabled when hosted in a context — like the
    /// onboarding tour's replay preview — that shouldn't steal focus.
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

                Spacer(minLength: 0)

                Button {
                    guard !isRequestingPermission else {
                        return
                    }
                    isRequestingPermission = true
                    permission.performRequest()
                    Task {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// A lightweight stand-in for ``AppPermissions`` used by the preview, so it
/// doesn't need to spin up the real manager and its app machinery.
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
