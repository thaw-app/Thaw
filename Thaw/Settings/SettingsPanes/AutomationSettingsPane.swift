//
//  AutomationSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct AutomationSettingsPane: View {
    @StateObject private var settings = AutomationSettings()
    @State private var newBundleId: String = ""
    @State private var isShowingAddError = false
    @State private var addErrorMessage = ""

    var body: some View {
        IceForm {
            enableSection

            if settings.isSettingsURIEnabled {
                whitelistSection
                aboutSection
            }
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        IceSection(options: [.isBordered]) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Settings URI Scheme", isOn: $settings.isSettingsURIEnabled)
                    .annotation("Allow external applications to read and modify Thaw settings via thaw:// URLs.")

                if !settings.isSettingsURIEnabled {
                    securityNote
                }
            }
        }
    }

    private var securityNote: some View {
        CalloutBox("Settings URI is disabled. External apps cannot read or modify Thaw settings.") {
            Image(systemName: "lock.fill")
                .foregroundStyle(.green)
        }
    }

    // MARK: - Whitelist Section

    private var whitelistSection: some View {
        IceSection(options: [.isBordered]) {
            VStack(alignment: .leading, spacing: 16) {
                whitelistHeader

                if settings.whitelistedApps.isEmpty {
                    emptyWhitelistView
                } else {
                    whitelistList
                }

                Divider()

                addAppSection
            }
        }
    }

    private var whitelistHeader: some View {
        HStack {
            Text("Whitelisted Applications")
                .font(.headline)

            Spacer()

            Text(String(format: NSLocalizedString("whitelisted_apps_count", comment: "Shows the number of whitelisted apps"), settings.whitelistedApps.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyWhitelistView: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No whitelisted apps")
                .font(.headline)

            Text("Apps that request settings access will appear here after you approve them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var whitelistList: some View {
        VStack(spacing: 8) {
            ForEach(settings.whitelistedApps) { app in
                whitelistedAppRow(app)
            }
        }
    }

    private func whitelistedAppRow(_ app: AutomationSettings.WhitelistedApp) -> some View {
        HStack(spacing: 12) {
            // App Icon
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }

            // App Info
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))

                Text(app.bundleId)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Permissions Info
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("Can modify settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Remove Button
            Button {
                settings.removeFromWhitelist(bundleId: app.bundleId)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove from whitelist")
            .accessibilityLabel("Remove \(app.displayName) from whitelist")
        }
        .padding(.vertical, 4)
    }

    private var addAppSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Application Manually")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Bundle Identifier (e.g., com.droppy)", text: $newBundleId)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    addBundleId()
                }
                .disabled({
                    let trimmed = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty || !AutomationSettings.isValidBundleId(trimmed)
                }())

                #if DEBUG
                    Button("Add Thaw (Test)") {
                        settings.addCurrentApp()
                    }
                    .help("Add Thaw itself for testing")
                #endif
            }

            if isShowingAddError {
                Text(addErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 12) {
                Text("How It Works")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                        Text("When an app sends a thaw:// URL to change settings, Thaw checks if that app is whitelisted.")
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                        Text("If not whitelisted, you'll see a confirmation dialog showing the app name and what it wants to do.")
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                        Text("If you approve, the app is permanently whitelisted and can modify settings anytime without asking again.")
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("4.")
                        Text("You can remove apps from this list at any time to revoke their access.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                Text("Supported Settings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Whitelisted apps can read settings, toggle boolean options, set numeric values (timers, delays), change enum settings (rehide strategy, Thaw Bar location), and modify per-display configurations. This includes auto-rehide, show on click/hover/scroll/double-click, Thaw Bar, hide application menus, enable always-hidden section, show tooltips, and diagnostic logging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func addBundleId() {
        let trimmed = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            showError("Bundle identifier cannot be empty.")
            return
        }

        guard AutomationSettings.isValidBundleId(trimmed) else {
            showError("Invalid bundle identifier format. Should be like 'com.company.appname'.")
            return
        }

        let existing = settings.whitelistedApps.contains { $0.bundleId == trimmed }
        guard !existing else {
            showError("'\(trimmed)' is already in the whitelist.")
            return
        }

        settings.addToWhitelist(bundleId: trimmed)
        newBundleId = ""
        isShowingAddError = false
    }

    private func showError(_ message: String) {
        addErrorMessage = message
        isShowingAddError = true
    }
}

// MARK: - Preview

#Preview {
    AutomationSettingsPane()
        .frame(width: 600, height: 500)
}
