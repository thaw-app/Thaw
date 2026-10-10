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
    @State private var newBundleId: String = ""
    @State private var isShowingAddError = false
    @State private var addErrorMessage = ""
    @State private var selectedHookProfileID: UUID?
    @State private var hookErrorMessage: String?
    /// Bumped whenever a per-profile hook write completes, so SwiftUI
    /// re-reads the latest values from ProfileManager.
    @State private var profileHookRevision: Int = 0
    /// Shared width for the hook-row label column, sized to the widest
    /// localized label so longer translations never wrap mid-word.
    @State private var hookLabelWidth: CGFloat = 90

    var body: some View {
        ThawForm {
            // Everyday options first: what happens on its own as you work.
            profileAutoSwitchSection

            ThawSection("Presentation") {
                Toggle("Enter Zen Mode while presenting", isOn: $advancedSettings.autoZenWhileSharingScreen)
                    .annotation(
                        "Hides your Hidden and Always Hidden items while a display is mirrored or your screen is shared, then brings them back.",
                        more: "macOS offers no way to see that another app is recording the screen, so recordings are not covered."
                    )
            }

            alertRevealSection

            // Then the parts that talk to other apps and run your own code.
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
        .errorAlert("Couldn’t save script", message: $hookErrorMessage)
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
        .onPreferenceChange(HookLabelWidthKey.self) { width in
            hookLabelWidth = max(width, 90)
        }
    }

    // MARK: - Profile Auto-Switch

    @ViewBuilder
    private var profileAutoSwitchSection: some View {
        // Only shown when profiles exist; an empty picker is noise.
        if !appState.profileManager.profiles.isEmpty {
            ProfileAutoSwitchControls(
                profileManager: appState.profileManager,
                errorMessage: $hookErrorMessage
            )
        }
    }

    // MARK: - Enable Section

    /// Opens the Advanced group. Off is the normal state, so it carries no
    /// warning when off; the sections that depend on it simply stay hidden.
    private var enableSection: some View {
        ThawSection {
            Text("Advanced")
                .font(ThawType.heading)
        } content: {
            Toggle("Allow other apps to change settings", isOn: $settings.isSettingsURIEnabled)
                .annotation("Apps you approve can read and change \(Constants.displayName) settings by opening thaw:// links.")
        }
    }

    // MARK: - Whitelist Section

    private var whitelistSection: some View {
        ThawSection {
            let count = String(localized: "apps \(settings.whitelistedApps.count)", comment: "Shows the number of allowed apps")
            HStack(spacing: ThawSpacing.compact) {
                Text("Allowed apps")
                Text(verbatim: "(\(count))")
                    .foregroundStyle(ThawInk.supporting)
            }
        } content: {
            if settings.whitelistedApps.isEmpty {
                emptyWhitelistView
            } else {
                ForEach(settings.whitelistedApps) { app in
                    whitelistedAppRow(app)
                        .contextMenu {
                            Button("Remove from Allowed Apps", role: .destructive) {
                                settings.removeFromWhitelist(bundleId: app.bundleId)
                            }
                        }
                }
            }
        }
    }

    private var emptyWhitelistView: some View {
        ThawEmptyState(
            systemImage: "checkmark.shield",
            title: "No allowed apps",
            caption: "An app appears here after it asks to change settings and you approve it."
        )
    }

    private func whitelistedAppRow(_ app: AutomationSettings.WhitelistedApp) -> some View {
        HStack(spacing: ThawSpacing.inset) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                Text(app.displayName)
                    .font(ThawType.label)
                Text(app.bundleId)
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
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
            .font(ThawType.caption)
            .foregroundStyle(ThawInk.supporting)

            Button {
                settings.removeFromWhitelist(bundleId: app.bundleId)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove from allowed apps")
            .accessibilityLabel("Remove \(app.displayName) from allowed apps")
        }
    }

    private var addAppSection: some View {
        ThawSection("Add an app") {
            HStack(spacing: ThawSpacing.base) {
                TextField("App bundle ID, e.g. com.example.App", text: $newBundleId)
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
                    .font(ThawType.caption)
                    .foregroundStyle(Color.warning)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        ThawSection("Approving an app") {
            VStack(alignment: .leading, spacing: ThawSpacing.base) {
                numberedStep(1, "When an app opens a thaw:// link to change settings, \(Constants.displayName) checks whether you have allowed that app.")
                numberedStep(2, "If you have not, you’ll see a confirmation dialog showing the app name and what it wants to do.")
                numberedStep(3, "If you approve, the app is allowed permanently and can modify settings anytime without asking again.")
                numberedStep(4, "You can remove apps from this list at any time to revoke their access.")
            }
            .font(ThawType.caption)
            .foregroundStyle(ThawInk.supporting)

            Text("Allowed apps can read and change most settings, such as how sections show and hide, the \(Constants.displayName) Bar, and per-display options.")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numberedStep(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: ThawSpacing.base) {
            Text(verbatim: "\(number).")
            Text(text)
        }
    }

    // MARK: - Actions

    private func addBundleId() {
        let trimmed = newBundleId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            showError("Enter a bundle ID, like com.example.App.")
            return
        }

        guard AutomationSettings.isValidBundleId(trimmed) else {
            showError("That isn’t a bundle ID. Enter one like com.example.App.")
            return
        }

        let existing = settings.whitelistedApps.contains { $0.bundleId == trimmed }
        guard !existing else {
            showError("“\(trimmed)” is already allowed.")
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
        ThawSection("Scripts for every profile") {
            Text("Run a shell script or AppleScript before or after any profile switch: by hand, with a keyboard shortcut, when displays change, or from a Focus filter.")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)

            HookRow(
                label: "Before switching",
                hook: $hookSettings.globalPreHook,
                labelWidth: hookLabelWidth
            )

            HookRow(
                label: "After switching",
                hook: $hookSettings.globalPostHook,
                labelWidth: hookLabelWidth
            )
        }
    }

    private var profileHooksSection: some View {
        ThawSection("Scripts for one profile") {
            if appState.profileManager.profiles.isEmpty {
                Text("No profiles yet. Create one on the Profiles page to give it its own scripts.")
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            } else {
                ThawPicker("Profile", selection: $selectedHookProfileID) {
                    ForEach(appState.profileManager.profiles) { meta in
                        Text(meta.name).tag(Optional(meta.id))
                    }
                }

                if let profileID = selectedHookProfileID {
                    HookRow(
                        label: "Before switching",
                        hook: bindingForProfileHook(profileID: profileID, phase: .pre),
                        labelWidth: hookLabelWidth
                    )

                    HookRow(
                        label: "After switching",
                        hook: bindingForProfileHook(profileID: profileID, phase: .post),
                        labelWidth: hookLabelWidth
                    )

                    Text("These run only when switching to this profile, between the scripts for every profile: after their Before switching script and before their After switching one.")
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                }
            }
        }
        .id(profileHookRevision)
    }

    private var envVarsSection: some View {
        ThawSection("Script environment") {
            Text("Environment variables passed to scripts")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)

            Text(verbatim: "THAW_HOOK_PHASE, THAW_HOOK_SCOPE, THAW_PROFILE_ID, THAW_PROFILE_NAME, THAW_PREVIOUS_PROFILE_ID, THAW_PREVIOUS_PROFILE_NAME")
                .font(ThawType.caption.monospaced())
                .foregroundStyle(ThawInk.supporting)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Example: a Before switching script could run `defaults write com.bjango.istatmenus5 ActiveProfile -string \"$THAW_PROFILE_NAME\"` to keep iStat Menus in sync with \(Constants.displayName).")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
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
                    // The row would otherwise keep showing a hook that was
                    // never written to the profile.
                    hookErrorMessage = error.localizedDescription
                }
            }
        )
    }

    // MARK: - Reveal on Icon Change

    private var alertRevealSection: some View {
        ThawSection("Reveal on icon change") {
            AlertRevealItemList()
            // The list shows only a "hide an item first" note when nothing
            // can reveal, and a cooldown for nothing would do nothing.
            if hasAlertRevealCandidates {
                alertRevealCooldown
            }
        }
    }

    /// Mirrors the rows AlertRevealItemList draws: any item in Hidden or
    /// Always Hidden, or an opt-in whose item has since left the menu bar.
    private var hasAlertRevealCandidates: Bool {
        let cache = appState.itemManager.itemCache
        return !(cache[.hidden] + cache[.alwaysHidden]).isEmpty
            || !MenuBarItemAlertReveals.identifiers().isEmpty
    }

    private var alertRevealCooldown: some View {
        SecondsSliderRow(
            "Reveal cooldown",
            value: $advancedSettings.menuBarItemAlertRevealCooldown,
            in: 5 ... 300,
            step: 5
        )
        .annotation(
            """
            The least time that passes before the same item can reveal itself again, \
            so an icon that animates continuously can’t bounce in and out of the menu bar.
            """
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
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            HStack(spacing: ThawSpacing.base) {
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
                    .font(ThawType.caption.monospaced())
                    .foregroundStyle(hook == nil ? ThawInk.supporting : Color.primary)
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
                .help("Remove script")
                .accessibilityLabel("Remove script")
                .opacity(hook == nil ? 0 : 1)
                .allowsHitTesting(hook != nil)
                .accessibilityHidden(hook == nil)
            }

            if hook != nil {
                HStack(spacing: ThawSpacing.gutter) {
                    Spacer().frame(width: labelWidth)

                    Toggle("Enabled", isOn: enabledBinding)
                        .toggleStyle(.checkbox)

                    HStack(spacing: ThawSpacing.tight) {
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
                    .font(ThawType.caption)

                    Spacer()
                }

                if let warning = validationWarning {
                    HStack(spacing: ThawSpacing.compact) {
                        Spacer().frame(width: labelWidth)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warning)
                        Text(warning)
                            .font(ThawType.caption)
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
            return String(localized: "Not executable. Run “chmod +x” on the file.")
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
    AutomationSettingsPane(
        settings: AutomationSettings(),
        hookSettings: AutomationHookSettings(),
        advancedSettings: AdvancedSettings()
    )
    .frame(width: 600, height: 500)
}
