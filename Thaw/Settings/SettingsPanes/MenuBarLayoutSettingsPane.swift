//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @Environment(AppState.self) var appState: AppState
    let itemManager: MenuBarItemManager
    @Bindable var advancedSettings: AdvancedSettings

    @State private var loadDeadlineReached = false
    @State private var isResettingLayout = false
    @State private var resetStatus: ResetStatus?
    @State private var isConfirmingReset = false
    @State private var maxSliderLabelWidth: CGFloat = 0
    @State private var isAdvancedExpanded = false

    /// Bumped whenever the screen the editor reflects may have changed, so
    /// the display title above the bars re-evaluates. Screen parameters cover
    /// displays arriving, leaving or being rearranged; app activation covers
    /// the menu bar moving to another screen without the layout changing.
    @State private var displayTitleRefreshToken = 0

    private let diagLog = DiagLog(category: "MenuBarLayoutPane")

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    private var areControlItemsDisabledBySystem: Bool {
        itemManager.areControlItemsMissing
    }

    var body: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermissions
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm {
                layoutBarsSection
                layoutSectionsCard
                iconPreviewsCard
                advancedLayoutControlsCard
                resetControls
            }
            .onAppear {
                // Enable background cache prewarming while the layout settings
                // pane is open.
                appState.imageCache.markSettingsPaneOpened()
            }
            .onDisappear {
                // Disable background cache prewarming once the layout settings
                // pane is no longer visible, bounding how long perpetual
                // background captures (including the leaking SkyLight offscreen
                // path) can run (#759).
                appState.imageCache.markSettingsPaneClosed()
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
            ) { _ in
                displayTitleRefreshToken &+= 1
            }
            .onReceive(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.didActivateApplicationNotification)
            ) { _ in
                displayTitleRefreshToken &+= 1
            }
        }
    }

    private var layoutSectionsCard: some View {
        IceSection("Sections") {
            Toggle(
                "Enable the always-hidden section",
                isOn: $advancedSettings.enableAlwaysHiddenSection
            )
            sectionDividerStyle
        }
    }

    private var iconPreviewsCard: some View {
        IceSection("Icon previews") {
            iconRefreshInterval
        }
    }

    private var advancedLayoutControlsCard: some View {
        IceSection {
            DisclosureGroup("Advanced layout controls", isExpanded: $isAdvancedExpanded) {
                automaticArrangementEnabled
                enableMenuBarItemOverflow
                if advancedSettings.enableMenuBarItemOverflow {
                    useThawBarOnNotchOverflow
                }
            }
        }
        .onChange(of: appState.navigationState.requestedSettingsDisclosure, initial: true) { _, _ in
            if SettingsSearchNavigation.consumeDisclosure(
                .advancedLayoutControls,
                navigationState: appState.navigationState
            ) {
                isAdvancedExpanded = true
            }
        }
    }

    /// Both strings are reused verbatim from the existing catalog so this
    /// control ships fully translated: "Arrange menu bar items." and the
    /// ⌘ Command + drag line already carry all 19 localizations. The
    /// trailing period in the toggle label is the catalog's, not a slip —
    /// matching the existing key exactly is what avoids a new translation
    /// round.
    private var automaticArrangementEnabled: some View {
        Toggle(
            "Arrange menu bar items.",
            isOn: $advancedSettings.automaticArrangementEnabled
        )
        .annotation {
            Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                .padding(.trailing, 75)
        }
    }

    private var enableMenuBarItemOverflow: some View {
        Toggle(
            "Enable menu bar item overflow",
            isOn: $advancedSettings.enableMenuBarItemOverflow
        )
        .annotation {
            Text(
                """
                Move menu bar items from the visible section into the hidden \
                section when they don't fit beside the notch on a notched \
                display. Disable to keep the saved profile layout exactly as \
                authored even when items would otherwise be pushed under the \
                notch.
                """
            )
            .padding(.trailing, 75)
        }
    }

    private var useThawBarOnNotchOverflow: some View {
        Toggle(
            "Use the Thaw Bar while items are overflowed",
            isOn: $advancedSettings.useThawBarOnNotchOverflow
        )
        .annotation {
            Text(
                """
                Reveal hidden items through the Thaw Bar while overflow has items \
                ejected. The visible row has no room left beside the notch at that \
                point, so expanding the hidden section inline cannot show them. \
                Disable to always follow the per-display Thaw Bar setting.
                """
            )
            .padding(.trailing, 75)
        }
    }

    private var sectionDividerStyle: some View {
        IcePicker("Section divider style", selection: $advancedSettings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    private var iconRefreshInterval: some View {
        let maxFPS = MenuBarItemImageCache.maxIconRefreshRate
        let fpsBinding = Binding<Double>(
            get: {
                let interval = advancedSettings.iconRefreshInterval
                return interval > 0 ? 1.0 / interval : 0
            },
            set: { advancedSettings.iconRefreshInterval = $0 > 0 ? 1.0 / $0 : 0 }
        )
        return LabeledContent {
            IceSlider(
                value: fpsBinding,
                in: 0 ... maxFPS,
                step: 1
            ) {
                Text(fpsBinding.wrappedValue > 0
                    ? "\(Int(fpsBinding.wrappedValue)) fps"
                    : "Off")
            }
        } label: {
            Text("Icon refresh rate")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("How often animated icons refresh in the visible section, Hidden Thaw Bar, Search, and Layout. Always Hidden stays at 1 fps. Higher values use more CPU.")
    }

    /// The name of the display whose layout the bars below are showing.
    ///
    /// The editor has no display picker: it always reflects the screen that
    /// currently owns the menu bar, which is what `LayoutBarContainer` and
    /// `LayoutBarPaddingView` both read. On a single Mac that is invisible,
    /// but with an external display as the primary the editor silently
    /// describes a different screen than the user is picturing — and the
    /// notch placeholder correctly disappearing is the symptom people
    /// actually notice (#886). Naming the display makes the existing
    /// behaviour legible instead of changing it.
    private var editingDisplayName: String? {
        guard NSScreen.screens.count > 1 else {
            return nil
        }
        let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        let name = screen?.localizedName.trimmingCharacters(in: .whitespaces)
        return (name?.isEmpty ?? true) ? nil : name
    }

    private var layoutBarsSection: some View {
        IceSection {
            if let editingDisplayName {
                Text("Active display: \(editingDisplayName)")
                    // Redrawn on the same signals LayoutBarPaddingView uses to
                    // re-evaluate the notch indicator, so the title and the
                    // bars below it can never disagree about which screen
                    // they are describing.
                    .id(displayTitleRefreshToken)
            }
        } content: {
            layoutBars
        } footer: {
            // Native grouped Section footer beneath the bars. Interpolated so
            // the three translated strings flow as one wrapping paragraph
            // instead of three fixed lines (Text + is deprecated on macOS 26;
            // each inner Text keeps its own localization key).
            Text("\(Text("Drag to arrange your menu bar items into different sections.")) \(Text("Move the New Items badge to choose where newly detected items will appear.")) \(Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar."))")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
        .opacity(hasItems ? 1 : 0.75)
        .blur(radius: hasItems ? 0 : 5)
        .allowsHitTesting(hasItems)
        .overlay {
            if !hasItems {
                VStack(spacing: 8) {
                    if loadDeadlineReached {
                        VStack(spacing: 4) {
                            if areControlItemsDisabledBySystem {
                                Text("One or more section dividers are hidden by macOS")
                                Text("Check System Settings > Menu Bar and enable \(Constants.displayName)")
                                    .font(.callout.bold())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Unable to load menu bar items")
                            }
                        }
                    } else {
                        Text("Loading menu bar items…")
                        ProgressView()
                    }
                }
            }
        }
        .task(id: hasItems) {
            loadDeadlineReached = false

            guard !hasItems, ScreenCapture.cachedCheckPermissions() else {
                return
            }

            diagLog.debug("Preloading menu bar layout caches (hasItems=\(self.hasItems), screenRecording=\(ScreenCapture.cachedCheckPermissions()))")

            async let preloadCaches: Void = preloadLayoutCaches()

            try? await Task.sleep(for: .seconds(3))

            if !Task.isCancelled, !hasItems {
                loadDeadlineReached = true
                diagLog.error("Menu bar layout failed to load items after 3s timeout. cacheItems: \(itemManager.itemCache.managedItems.count), images: \(appState.imageCache.images.count), displayID: \(self.itemManager.itemCache.displayID.map { "\($0)" } ?? "nil")")
            }

            await preloadCaches
        }
    }

    private var resetControls: some View {
        IceSection {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reset menu bar layout")
                        .font(.headline)
                    Text("Resets dividers and moves every movable item except the \(Constants.displayName) icon to the selected section.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    isConfirmingReset = true
                } label: {
                    if isResettingLayout {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Reset Layout…")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResettingLayout || areControlItemsDisabledBySystem)
            }

            if isConfirmingReset {
                resetTargetControls
            }

            if let resetStatus {
                Text(resetStatus.message)
                    .font(.footnote)
                    .foregroundStyle(resetStatus.isError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var resetTargetControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose where to move the menu bar items:")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Visible") { resetMenuBarLayout(to: .visible) }
                Button("Hidden") { resetMenuBarLayout(to: .hidden) }
                if appState.settings.advanced.enableAlwaysHiddenSection {
                    Button("Always Hidden") { resetMenuBarLayout(to: .alwaysHidden) }
                }
                Button("Cancel", role: .cancel) {
                    isConfirmingReset = false
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var cannotArrange: some View {
        Text("\(Constants.displayName) cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var missingScreenRecordingPermissions: some View {
        VStack {
            Text("Menu bar layout requires screen recording permissions.")
                .font(.title2)

            Button {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            } label: {
                Text("Go to Advanced Settings")
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                LayoutBar(imageCache: appState.imageCache, section: name)
            }
        }
    }

    private func resetMenuBarLayout(to target: MenuBarItemManager.LayoutResetTarget) {
        isConfirmingReset = false
        isResettingLayout = true
        resetStatus = nil

        let manager = itemManager

        Task { @MainActor in
            do {
                let failedMoves = switch target {
                case .visible:
                    try await manager.resetLayoutToVisible()
                case .hidden:
                    try await manager.resetLayoutToFreshState()
                case .alwaysHidden:
                    try await manager.resetLayoutToAlwaysHidden()
                }
                if failedMoves == 0 {
                    resetStatus = .success(target)
                } else {
                    resetStatus = .partialFailure(failedMoves)
                }
                isResettingLayout = false

                // The manager rebuilds both caches before returning.
            } catch {
                resetStatus = .failure(error.localizedDescription)
                isResettingLayout = false
            }
        }
    }

    private func preloadLayoutCaches() async {
        await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        guard !Task.isCancelled else {
            return
        }

        diagLog.debug("Preload: itemCache after cacheItemsRegardless: managedItems=\(self.itemManager.itemCache.managedItems.count), visible=\(self.itemManager.itemCache[.visible].count), hidden=\(self.itemManager.itemCache[.hidden].count), alwaysHidden=\(self.itemManager.itemCache[.alwaysHidden].count)")

        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
        guard !Task.isCancelled else {
            return
        }

        diagLog.debug("Preload: imageCache after update: \(self.appState.imageCache.images.count) images")
    }

    private enum ResetStatus {
        case success(MenuBarItemManager.LayoutResetTarget)
        case partialFailure(Int)
        case failure(String)

        var message: String {
            switch self {
            case .success(.visible):
                String(localized: "Items were moved to the Visible section.")
            case .success(.hidden):
                String(localized: "Layout reset. Items were moved to the Hidden section.")
            case .success(.alwaysHidden):
                String(localized: "Layout reset. Items were moved to the Always Hidden section.")
            case let .partialFailure(count):
                String(localized: "Reset completed with \(count) item(s) that could not be moved. Check the menu bar and try again if needed.")
            case let .failure(message):
                String(localized: "Reset failed: \(message)")
            }
        }

        var isError: Bool {
            switch self {
            case .failure, .partialFailure:
                true
            case .success:
                false
            }
        }
    }
}
