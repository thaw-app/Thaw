//
//  AutomationSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AutomationSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var settings = AutomationSettings()
    @StateObject private var hookSettings = AutomationHookSettings()
    @State private var newBundleId: String = ""
    @State private var isShowingAddError = false
    @State private var addErrorMessage = ""
    @State private var selectedHookProfileID: UUID?
    /// Bumped whenever a per-profile hook write completes, so SwiftUI
    /// re-reads the latest values from ProfileManager.
    @State private var profileHookRevision: Int = 0

    var body: some View {
        IceForm {
            enableSection

            if settings.isSettingsURIEnabled {
                whitelistSection
                aboutSection
            }

            profileHooksSection
        }
        .onAppear {
            if selectedHookProfileID == nil {
                selectedHookProfileID = appState.profileManager.activeProfileID
                    ?? appState.profileManager.profiles.first?.id
            }
        }
        .onChange(of: appState.profileManager.profiles) { _, updated in
            // The selected profile can disappear out from under the
            // picker (delete from the Profiles pane, import-replace,
            // etc.). Reset to the active profile if any, otherwise
            // the first remaining profile, so the picker and the
            // per-profile HookRow bindings always reference a profile
            // that actually exists.
            let ids = Set(updated.map(\.id))
            if let current = selectedHookProfileID, !ids.contains(current) {
                selectedHookProfileID = appState.profileManager.activeProfileID
                    ?? updated.first?.id
            }
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        IceSection(options: [.isBordered]) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Settings URI Scheme", isOn: $settings.isSettingsURIEnabled)
                    .annotation("Allow external applications to read and modify \(Constants.displayName) settings via thaw:// URLs.")

                if !settings.isSettingsURIEnabled {
                    securityNote
                }
            }
            .padding(8)
        }
    }

    private var securityNote: some View {
        CalloutBox("Settings URI is disabled. External apps cannot read or modify \(Constants.displayName) settings.") {
            Image(systemName: "lock.fill")
                .foregroundStyle(.green)
        }
    }

    // MARK: - Whitelist Section

    private var whitelistSection: some View {
        IceSection(spacing: .iceSectionDefaultSpacing, options: [.isBordered]) {
            whitelistHeader
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                if settings.whitelistedApps.isEmpty {
                    emptyWhitelistView
                } else {
                    whitelistList
                }

                Divider()

                addAppSection
            }
            .padding(8)
        }
    }

    private var whitelistHeader: some View {
        HStack(spacing: 0) {
            Text("Whitelisted Applications")
                .font(.headline)

            Spacer().frame(width: 6)

            Text("(")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "apps \(settings.whitelistedApps.count)", comment: "Shows the number of whitelisted apps"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
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
                TextField("Bundle Identifier (e.g., iordv.Droppy)", text: $newBundleId)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    addBundleId()
                }
                .disabled({
                    let trimmed = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty || !AutomationSettings.isValidBundleId(trimmed)
                }())

                #if DEBUG
                    Button("Add \(Constants.displayName) (Test)") {
                        settings.addCurrentApp()
                    }
                    .help("Add \(Constants.displayName) itself for testing")
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

                Text("Whitelisted apps can read settings, toggle boolean options, set numeric values (timers, delays), change enum settings (rehide strategy, \(Constants.displayName) Bar location), and modify per-display configurations. This includes auto-rehide, show on click/hover/scroll/double-click, \(Constants.displayName) Bar, hide application menus, enable always-hidden section, show tooltips, and diagnostic logging.")
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

    // MARK: - Profile Hooks Section

    private var profileHooksSection: some View {
        IceSection(spacing: .iceSectionDefaultSpacing, options: [.isBordered]) {
            HStack(spacing: 0) {
                Text("Hooks").font(.headline)
                Spacer()
            }
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                Text("Run a shell or AppleScript file before or after a profile switch. Hooks fire on every apply path: manual button, hotkey, display auto-switch, and Focus Filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                globalHooksGroup

                Divider()

                profileHooksGroup

                Divider()

                envVarsHelp
            }
            .padding(8)
        }
    }

    private var globalHooksGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Hooks").font(.headline)

            Divider()

            HookRow(
                label: "Pre-apply",
                hook: $hookSettings.globalPreHook
            )

            HookRow(
                label: "Post-apply",
                hook: $hookSettings.globalPostHook
            )
        }
    }

    @ViewBuilder
    private var profileHooksGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Per-Profile Hooks").font(.headline)
                Spacer()
                if !appState.profileManager.profiles.isEmpty {
                    Picker(selection: $selectedHookProfileID) {
                        ForEach(appState.profileManager.profiles) { meta in
                            Text(meta.name).tag(Optional(meta.id))
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Divider()

            if appState.profileManager.profiles.isEmpty {
                Text("No profiles saved yet. Create one in the Profiles tab to attach per-profile hooks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let profileID = selectedHookProfileID {
                HookRow(
                    label: "Pre-apply",
                    hook: bindingForProfileHook(profileID: profileID, phase: .pre)
                )

                HookRow(
                    label: "Post-apply",
                    hook: bindingForProfileHook(profileID: profileID, phase: .post)
                )

                Divider()

                Text("These hooks run only when this profile is applied, after the global pre-hook and before the global post-hook.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .id(profileHookRevision)
    }

    private var envVarsHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Environment variables passed to scripts").font(.subheadline).foregroundStyle(.secondary)
            Text("THAW_HOOK_PHASE, THAW_HOOK_SCOPE, THAW_PROFILE_ID, THAW_PROFILE_NAME, THAW_PREVIOUS_PROFILE_ID, THAW_PREVIOUS_PROFILE_NAME")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Example: a bash pre-hook could `defaults write com.bjango.istatmenus5 ActiveProfile -string \"$THAW_PROFILE_NAME\"` to keep iStat Menus in sync with Thaw.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func bindingForProfileHook(profileID: UUID, phase: HookPhase) -> Binding<HookScript?> {
        Binding(
            get: {
                let automation = appState.profileManager.hooks(forProfileID: profileID)
                return phase == .pre ? automation.preHook : automation.postHook
            },
            set: { newValue in
                do {
                    try appState.profileManager.setHook(newValue, phase: phase, forProfileID: profileID)
                    profileHookRevision &+= 1
                } catch {
                    DiagLog(category: "AutomationSettingsPane").error(
                        "Failed to save \(phase.rawValue) hook for profile \(profileID): \(error)"
                    )
                }
            }
        )
    }
}

// MARK: - HookRow

private struct HookRow: View {
    let label: LocalizedStringKey
    @Binding var hook: HookScript?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .frame(width: 90, alignment: .leading)

                Text(displayPath)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(hook == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Choose Script...") { chooseScript() }
                    .buttonStyle(.bordered)

                if hook != nil {
                    Button(role: .destructive) {
                        hook = nil
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Clear hook")
                }
            }

            if hook != nil {
                HStack(spacing: 16) {
                    Spacer().frame(width: 90)

                    Toggle("Enabled", isOn: enabledBinding)
                        .toggleStyle(.checkbox)

                    HStack(spacing: 4) {
                        Text("Timeout")
                        TextField(value: timeoutBinding, format: .number) {
                            EmptyView()
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                        Stepper(value: timeoutBinding, in: 1...300) {
                            EmptyView()
                        }
                        .labelsHidden()
                        Text("s").foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    Spacer()
                }

                if let warning = validationWarning {
                    HStack(spacing: 6) {
                        Spacer().frame(width: 90)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var displayPath: String {
        if let path = hook?.path, !path.isEmpty {
            return path
        }
        return String(localized: "(no script selected)")
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
            get: { hook?.timeoutSeconds ?? 5 },
            set: { newValue in
                guard var current = hook else { return }
                current.timeoutSeconds = max(1, min(newValue, 300))
                hook = current
            }
        )
    }

    private var validationWarning: String? {
        guard let path = hook?.path else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return String(localized: "File does not exist.")
        }
        let ext = (path as NSString).pathExtension.lowercased()
        let appleScriptExts: Set<String> = ["scpt", "applescript", "scptd"]
        if !appleScriptExts.contains(ext), !fm.isExecutableFile(atPath: path) {
            return String(localized: "Not executable. Run \"chmod +x\" on the file.")
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

// MARK: - Preview

#Preview {
    AutomationSettingsPane()
        .frame(width: 600, height: 500)
}
