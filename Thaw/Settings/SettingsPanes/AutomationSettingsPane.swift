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
    @Environment(AppState.self) var appState: AppState
    @State private var settings = AutomationSettings()
    @State private var hookSettings = AutomationHookSettings()
    @State private var newBundleId: String = ""
    @State private var isShowingAddError = false
    @State private var addErrorMessage = ""
    @State private var selectedHookProfileID: UUID?
    /// Bumped whenever a per-profile hook write completes, so SwiftUI
    /// re-reads the latest values from ProfileManager.
    @State private var profileHookRevision: Int = 0
    /// Shared width for the hook-row label column, sized to the widest
    /// localized label so longer translations never wrap mid-word.
    @State private var hookLabelWidth: CGFloat = 90

    var body: some View {
        IceForm {
            enableSection

            if settings.isSettingsURIEnabled {
                whitelistSection
                addAppSection
                aboutSection
            }

            globalHooksSection
            profileHooksSection
            envVarsSection
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
        .onPreferenceChange(HookLabelWidthKey.self) { width in
            hookLabelWidth = max(width, 90)
        }
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        IceSection {
            Toggle("Enable Settings URI Scheme", isOn: $settings.isSettingsURIEnabled)
                .annotation("Allow external applications to read and modify \(Constants.displayName) settings via thaw:// URLs.")

            if !settings.isSettingsURIEnabled {
                SettingsWarningPill(
                    title: "Settings URI disabled",
                    message: "External apps cannot read or modify \(Constants.displayName) settings.",
                    systemImage: "lock.circle.fill"
                )
            }
        }
    }

    // MARK: - Whitelist Section

    private var whitelistSection: some View {
        IceSection {
            let count = String(localized: "apps \(settings.whitelistedApps.count)", comment: "Shows the number of whitelisted apps")
            HStack(spacing: 6) {
                Text("Whitelisted Applications")
                Text(verbatim: "(\(count))")
                    .foregroundStyle(.secondary)
            }
        } content: {
            if settings.whitelistedApps.isEmpty {
                emptyWhitelistView
            } else {
                ForEach(settings.whitelistedApps) { app in
                    whitelistedAppRow(app)
                }
            }
        }
    }

    private var emptyWhitelistView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No whitelisted apps")
                .font(.body.weight(.medium))
            Text("Apps that request settings access will appear here after you approve them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func whitelistedAppRow(_ app: AutomationSettings.WhitelistedApp) -> some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body.weight(.medium))
                Text(app.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Label {
                Text("Can modify settings")
            } icon: {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(.secondary)

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
    }

    private var addAppSection: some View {
        IceSection("Add Application") {
            HStack(spacing: 8) {
                TextField("Bundle Identifier (e.g., iordv.Droppy)", text: $newBundleId)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    addBundleId()
                }
                .buttonStyle(.settingsGlass)
                .disabled({
                    let trimmed = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty || !AutomationSettings.isValidBundleId(trimmed)
                }())

                #if DEBUG
                    Button("Add \(Constants.displayName) (Test)") {
                        settings.addCurrentApp()
                    }
                    .buttonStyle(.settingsGlass)
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
        IceSection("How It Works") {
            VStack(alignment: .leading, spacing: 8) {
                numberedStep(1, "When an app sends a thaw:// URL to change settings, Thaw checks if that app is whitelisted.")
                numberedStep(2, "If not whitelisted, you'll see a confirmation dialog showing the app name and what it wants to do.")
                numberedStep(3, "If you approve, the app is permanently whitelisted and can modify settings anytime without asking again.")
                numberedStep(4, "You can remove apps from this list at any time to revoke their access.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Whitelisted apps can read settings, toggle boolean options, set numeric values (timers, delays), change enum settings (rehide strategy, \(Constants.displayName) Bar location), and modify per-display configurations. This includes auto-rehide, show on click/hover/scroll/double-click, \(Constants.displayName) Bar, hide application menus, enable always-hidden section, show tooltips, and diagnostic logging.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numberedStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(number).")
            Text(text)
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

    // MARK: - Hooks

    private var globalHooksSection: some View {
        IceSection("Global Hooks") {
            Text("Run a shell or AppleScript file before or after a profile switch. Hooks fire on every apply path: manual button, hotkey, display auto-switch, and Focus Filter.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HookRow(
                label: "Pre-apply",
                hook: $hookSettings.globalPreHook,
                labelWidth: hookLabelWidth
            )

            HookRow(
                label: "Post-apply",
                hook: $hookSettings.globalPostHook,
                labelWidth: hookLabelWidth
            )
        }
    }

    private var profileHooksSection: some View {
        IceSection("Per-Profile Hooks") {
            if appState.profileManager.profiles.isEmpty {
                Text("No profiles saved yet. Create one in the Profiles tab to attach per-profile hooks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                IcePicker("Profile", selection: $selectedHookProfileID) {
                    ForEach(appState.profileManager.profiles) { meta in
                        Text(meta.name).tag(Optional(meta.id))
                    }
                }

                if let profileID = selectedHookProfileID {
                    HookRow(
                        label: "Pre-apply",
                        hook: bindingForProfileHook(profileID: profileID, phase: .pre),
                        labelWidth: hookLabelWidth
                    )

                    HookRow(
                        label: "Post-apply",
                        hook: bindingForProfileHook(profileID: profileID, phase: .post),
                        labelWidth: hookLabelWidth
                    )

                    Text("These hooks run only when this profile is applied, after the global pre-hook and before the global post-hook.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id(profileHookRevision)
    }

    private var envVarsSection: some View {
        IceSection("Script Environment") {
            Text("Environment variables passed to scripts")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "THAW_HOOK_PHASE, THAW_HOOK_SCOPE, THAW_PROFILE_ID, THAW_PROFILE_NAME, THAW_PREVIOUS_PROFILE_ID, THAW_PREVIOUS_PROFILE_NAME")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Example: a bash pre-hook could `defaults write com.bjango.istatmenus5 ActiveProfile -string \"$THAW_PROFILE_NAME\"` to keep iStat Menus in sync with Thaw.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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

/// Collects the widest natural label width across all hook rows so the
/// label column can be sized to fit the longest localized string.
private struct HookLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HookRow: View {
    let label: LocalizedStringKey
    @Binding var hook: HookScript?
    let labelWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HookLabelWidthKey.self,
                                value: proxy.size.width
                            )
                        }
                    )
                    .frame(minWidth: labelWidth, alignment: .leading)

                Text(displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(hook == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Choose Script…") { chooseScript() }
                    .buttonStyle(.settingsGlass)

                Button(role: .destructive) {
                    hook = nil
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Clear hook")
                .opacity(hook == nil ? 0 : 1)
                .allowsHitTesting(hook != nil)
                .accessibilityHidden(hook == nil)
            }

            if hook != nil {
                HStack(spacing: 16) {
                    Spacer().frame(width: labelWidth)

                    Toggle("Enabled", isOn: enabledBinding)
                        .toggleStyle(.checkbox)

                    HStack(spacing: 4) {
                        Text("Timeout")
                        TextField(value: timeoutBinding, formatter: Self.timeoutFormatter) {
                            EmptyView()
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                        Stepper(value: timeoutBinding, in: 1 ... 300) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                    .font(.caption)

                    Spacer()
                }

                if let warning = validationWarning {
                    HStack(spacing: 6) {
                        Spacer().frame(width: labelWidth)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warning)
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(Color.warning)
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
        let appleScriptExts: Set = ["scpt", "applescript", "scptd"]
        if !appleScriptExts.contains(ext), !fm.isExecutableFile(atPath: path) {
            return String(localized: "Not executable. Run \"chmod +x\" on the file.")
        }
        return nil
    }

    private static let timeoutFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let suffix = " " + String(localized: "s", comment: "Seconds unit suffix for timeout field")
        f.positiveSuffix = suffix
        f.negativeSuffix = suffix
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 0
        return f
    }()

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
