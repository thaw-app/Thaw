//
//  PermissionsView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var manager: AppPermissions

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
        VStack(spacing: 0) {
            headerView
                .padding(.vertical)

            permissionsStack

            footerView
                .padding(.vertical)
        }
        .padding(.horizontal)
        .frame(width: 550)
        .fixedSize()
        .onAppear {
            checkForIceSettings()
            showImportIceSettings = hasIceSettings && !Defaults.bool(forKey: .hasCompletedFirstLaunch)
        }
    }

    private var headerView: some View {
        Label {
            Text("Permissions")
                .font(.system(size: 40, weight: .medium))
        } icon: {
            if let nsImage = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 85, height: 85)
            }
        }
    }

    private var explanationBox: some View {
        IceSection {
            VStack {
                Text("\(Constants.displayName) needs your permission to manage the menu bar.")
                    .fontWeight(.medium)
                Text("Absolutely no personal information is collected or stored.")
                    .bold()
                    .foregroundStyle(Color(red: 0.5, green: 0.75, blue: 1))
            }
            .padding()
        }
        .font(.title3)
    }

    private var permissionsStack: some View {
        VStack {
            if showImportIceSettings {
                iceImportBox
            }

            explanationBox
            ForEach(manager.allPermissions) { permission in
                permissionBox(permission)
            }
        }
    }

    private var footerView: some View {
        HStack {
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
    }

    private var continueButton: some View {
        Button {
            appState.dismissWindow(.permissions)

            guard manager.permissionsState != .missing else {
                appState.performSetup(hasPermissions: false)
                Defaults.set(true, forKey: .hasCompletedFirstLaunch)
                return
            }

            appState.performSetup(hasPermissions: true)
            Defaults.set(true, forKey: .hasCompletedFirstLaunch)

            Task {
                appState.activate(withPolicy: .regular)
                appState.openWindow(.settings)
            }
        } label: {
            Text(continueButtonText)
                .frame(maxWidth: .infinity)
                .foregroundStyle(continueButtonForegroundStyle)
        }
        .disabled(manager.permissionsState == .missing)
    }

    private func permissionBox(_ permission: Permission) -> some View {
        IceSection {
            VStack(spacing: 12) {
                Text(permission.title)
                    .font(.title.weight(.medium))
                    .underline()

                VStack(spacing: 2) {
                    Text("\(Constants.displayName) needs this to:")
                        .font(.title3)
                        .bold()

                    VStack(alignment: .leading) {
                        ForEach(permission.details, id: \.self) { detail in
                            HStack {
                                Text("•").bold()
                                Text(detail).fontWeight(.medium)
                            }
                        }
                    }
                }

                Button {
                    permission.performRequest()
                    Task {
                        await permission.waitForPermission()
                        appState.activate(withPolicy: .regular)
                        appState.openWindow(.permissions)
                    }
                } label: {
                    if permission.hasPermission {
                        Text("Permission Granted")
                            .foregroundStyle(.green)
                    } else {
                        Text("Grant Permission")
                    }
                }
                .allowsHitTesting(!permission.hasPermission)

                if !permission.isRequired {
                    CalloutBox("\(Constants.displayName) can work in a limited mode without this permission.") {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
        }
    }

    private var iceImportBox: some View {
        IceSection {
            VStack(spacing: 12) {
                Text("Import Settings")
                    .font(.title.weight(.medium))
                    .underline()

                VStack(spacing: 2) {
                    Text("We found settings from Ice (the original app).")
                        .font(.title3)
                        .bold()

                    if let result = iceImportResult {
                        if result.success {
                            Text("Successfully imported \(result.settingsImported) settings!")
                                .font(.title3)
                                .foregroundStyle(.green)
                                .bold()
                        } else {
                            Text("Import failed. You can configure settings manually.")
                                .font(.title3)
                                .foregroundStyle(.red)
                                .bold()
                        }
                    } else {
                        Text("Would you like to import your existing configuration?")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Icon positions cannot be restored.")
                            .font(.calloutBox)
                            .bold()
                            .foregroundStyle(.red)
                    }
                }

                if iceImportResult?.success == true {
                    // Disabled status label — no action needed.
                    Button("Imported") {}
                        .foregroundStyle(.green)
                        .disabled(true)
                } else {
                    Button("Import Settings") {
                        importIceSettings()
                    }
                    .disabled(isImportingIceSettings)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
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
                // Mark first launch as completed after successful import
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
