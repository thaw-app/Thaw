//
//  AutomationSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

struct AutomationSettingsPane: View {
    @Environment(AppState.self) var appState
    @Bindable var settings: AutomationSettings
    @Bindable var hookSettings: AutomationHookSettings
    @Bindable var advancedSettings: AdvancedSettings
    @State private var isChoosingApp = false
    @State private var isShowingAddError = false
    @State private var addErrorMessage = ""
    @State private var selectedHookProfileID: UUID?
    @State private var hookErrorMessage: String?
    /// Bumped whenever a per-profile hook write completes, so SwiftUI
    /// re-reads the latest values from ProfileManager.
    @State private var profileHookRevision: Int = 0
    @State private var isEditingProfileSwitching = false
    @State private var isShowingScriptEnvironment = false

    var body: some View {
        ThawForm {
            ThawSection {
                if !appState.profileManager.profiles.isEmpty {
                    profileSwitchingRow
                }

                Toggle(isOn: $advancedSettings.autoZenWhileSharingScreen) {
                    ThawRowLabel(
                        "Hide items while presenting",
                        detail: "Hidden items stay hidden while you share your screen or mirror a display."
                    )
                }
                .help("macOS offers no way to see that another app is recording the screen, so recordings are not covered.")
            }

            otherAppsSection
            scriptsSection
        }
        .errorAlert("Couldn’t save script", message: $hookErrorMessage)
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.application]) { result in
            addChosenApp(result)
        }
        .sheet(isPresented: $isEditingProfileSwitching) {
            AutomationSheet(title: "Profile switching") {
                ProfileAutoSwitchControls(
                    profileManager: appState.profileManager,
                    errorMessage: $hookErrorMessage
                )
            }
        }
        .onAppear {
            if selectedHookProfileID == nil {
                selectedHookProfileID = appState.profileManager.activeProfileID
                    ?? appState.profileManager.profiles.first?.id
            }
        }
        .onChange(of: appState.profileManager.profiles) { _, updated in
            // The selected profile can be deleted elsewhere; fall back to the
            // active one, else the first, so bindings never dangle.
            let ids = Set(updated.map(\.id))
            if let current = selectedHookProfileID, !ids.contains(current) {
                selectedHookProfileID = appState.profileManager.activeProfileID
                    ?? updated.first?.id
            }
        }
    }

    // MARK: - As you work

    private var profileSwitchingRow: some View {
        LabeledContent {
            Button("Choose…") { isEditingProfileSwitching = true }
                .buttonStyle(.settingsGlass)
        } label: {
            ThawRowLabel(
                "Switch profiles by display or Space",
                verbatimDetail: AutomationSummary.profileSwitching(profileAssignments)
            )
        }
    }

    private var profileAssignments: [AutomationSummary.Assignment] {
        appState.profileManager.profiles.flatMap { profile -> [AutomationSummary.Assignment] in
            var assignments = [AutomationSummary.Assignment]()
            if profile.associatedDisplayUUID != nil {
                let place = profile.associatedDisplayName ?? String(localized: "a display")
                assignments.append(.init(profile: profile.name, place: place))
            }
            if profile.associatedSpaceKey != nil {
                let place = profile.associatedSpaceName ?? String(localized: "a Space")
                assignments.append(.init(profile: profile.name, place: place))
            }
            return assignments
        }
    }

    // MARK: - Other apps

    private var otherAppsSection: some View {
        ThawSection("Other apps") {
            Toggle(isOn: $settings.isSettingsURIEnabled) {
                ThawRowLabel(
                    "Let apps change settings",
                    detail: "Apps you approve can change \(Constants.displayName) with thaw:// links. Each new app asks you once."
                )
            }

            if settings.isSettingsURIEnabled {
                ForEach(settings.whitelistedApps) { app in
                    allowedAppRow(app)
                }

                HStack(spacing: ThawSpacing.base) {
                    Button("Choose App…") { isChoosingApp = true }
                        .buttonStyle(.settingsGlass)

                    #if DEBUG
                        Button("Add \(Constants.displayName) (Test)") {
                            settings.addCurrentApp()
                        }
                        .buttonStyle(.settingsGlass)
                    #endif
                }

                if isShowingAddError {
                    Text(addErrorMessage)
                        .font(ThawType.caption)
                        .foregroundStyle(Color.warning)
                }
            }
        }
    }

    private func allowedAppRow(_ app: AutomationSettings.WhitelistedApp) -> some View {
        HStack(spacing: ThawSpacing.row) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app")
                        .foregroundStyle(ThawInk.supporting)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            Text(app.displayName)
                .help(app.bundleId)

            Spacer()

            Button("Remove") {
                settings.removeFromWhitelist(bundleId: app.bundleId)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThawInk.supporting)
            .accessibilityLabel("Remove \(app.displayName)")
        }
    }

    private func addChosenApp(_ result: Result<URL, Error>) {
        guard let url = try? result.get() else {
            showError("The app could not be selected. Try again.")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        switch AutomationSettings.choice(forBundleID: bundleID, allowed: settings.whitelistedApps.map(\.bundleId)) {
        case let .add(bundleID):
            settings.addToWhitelist(bundleId: bundleID)
            isShowingAddError = false
        case .alreadyAllowed:
            showError("“\(FileManager.default.displayName(atPath: url.path))” is already allowed.")
        case .noBundleID:
            showError("Choose an application with a bundle identifier.")
        }
    }

    private func showError(_ message: String) {
        addErrorMessage = message
        isShowingAddError = true
    }

    // MARK: - Scripts

    private var scriptsSection: some View {
        ThawSection {
            Text("Scripts when a profile switches")
        } content: {
            HookRow(label: "Before switching", hook: $hookSettings.globalPreHook)
            HookRow(label: "After switching", hook: $hookSettings.globalPostHook)

            if !appState.profileManager.profiles.isEmpty {
                LabeledContent {
                    ThawPicker("Profile", selection: $selectedHookProfileID) {
                        ForEach(appState.profileManager.profiles) { meta in
                            Text(meta.name).tag(Optional(meta.id))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    ThawRowLabel(
                        "Scripts for one profile",
                        detail: "They run between the two above, only when switching to this profile."
                    )
                }

                if let profileID = selectedHookProfileID {
                    Group {
                        HookRow(label: "Before switching", hook: bindingForProfileHook(profileID: profileID, phase: .pre))
                        HookRow(label: "After switching", hook: bindingForProfileHook(profileID: profileID, phase: .post))
                    }
                    .id(profileHookRevision)
                }
            }
        } footer: {
            Button("What scripts receive") { isShowingScriptEnvironment = true }
                .buttonStyle(.link)
                .popover(isPresented: $isShowingScriptEnvironment) {
                    scriptEnvironment
                }
        }
    }

    private var scriptEnvironment: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.base) {
            Text("Scripts get these environment variables:")
            Text(verbatim: "THAW_HOOK_PHASE\nTHAW_HOOK_SCOPE\nTHAW_PROFILE_ID\nTHAW_PROFILE_NAME\nTHAW_PREVIOUS_PROFILE_ID\nTHAW_PREVIOUS_PROFILE_NAME")
                .font(ThawType.caption.monospaced())
                .textSelection(.enabled)
            Text("For example, `defaults write com.bjango.istatmenus5 ActiveProfile -string \"$THAW_PROFILE_NAME\"` keeps iStat Menus on the same profile.")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
                .textSelection(.enabled)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 320, alignment: .leading)
        .padding(ThawSpacing.gutter)
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
                    // The row would otherwise keep showing a hook that was
                    // never written to the profile.
                    hookErrorMessage = error.localizedDescription
                }
            }
        )
    }
}

// MARK: - AutomationSheet

/// A sheet holding the controls that a summary row on the page opens.
private struct AutomationSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(ThawType.heading)
                .padding(.top, ThawSpacing.gutter)
            ThawForm {
                content
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.settingsGlass)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(ThawSpacing.gutter)
        }
        .frame(width: 520, height: 460)
    }
}

// MARK: - HookRow

private struct HookRow: View {
    let label: LocalizedStringKey
    @Binding var hook: HookScript?

    /// Timeouts offered in the menu; a stored value outside them is added.
    private static let timeouts: [Double] = [5, 10, 30, 60, 120, 300]

    var body: some View {
        LabeledContent {
            HStack(spacing: ThawSpacing.base) {
                Button(hook == nil ? "Choose…" : "Change…") { chooseScript() }
                    .buttonStyle(.settingsGlass)

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
            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text(label)
                if let warning = validationWarning {
                    Text(warning)
                        .font(ThawType.detail)
                        .foregroundStyle(Color.warning)
                } else {
                    Text(detail)
                        .font(ThawType.detail.monospaced())
                        .foregroundStyle(ThawInk.supporting)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var detail: String {
        let path = AutomationSummary.script(path: hook?.path)
        guard let hook, !hook.isEnabled else { return path }
        return String(localized: "\(path), off")
    }

    private var timeoutChoices: [Double] {
        let current = hook?.timeoutSeconds ?? 5
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

// MARK: - Preview

#Preview {
    AutomationSettingsPane(
        settings: AutomationSettings(),
        hookSettings: AutomationHookSettings(),
        advancedSettings: AdvancedSettings()
    )
    .frame(width: 600, height: 500)
}
