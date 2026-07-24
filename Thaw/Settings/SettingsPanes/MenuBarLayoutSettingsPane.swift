//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager
    @ObservedObject var advancedSettings: AdvancedSettings

    @State private var loadDeadlineReached = false
    @State private var isResettingLayout = false
    @State private var resetStatus: ResetStatus?
    @State private var isConfirmingReset = false
    @State private var maxSliderLabelWidth: CGFloat = 0
    @State private var isAdvancedExpanded = false

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
                enableMenuBarItemOverflow
                useLCSSortingOnNotchedDisplays
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

    private var useLCSSortingOnNotchedDisplays: some View {
        Toggle(
            "Use LCS sorting on notched displays",
            isOn: $advancedSettings.useLCSSortingOnNotchedDisplays
        )
        .annotation {
            Text(
                """
                Use the faster LCS (Longest Common Subsequence) algorithm for \
                profile sorting on notched displays instead of the full sort. \
                LCS minimises the number of moves but may be less reliable on \
                notched displays with smaller resolutions.
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
        let fpsBinding = Binding<Double>(
            get: {
                let interval = advancedSettings.iconRefreshInterval
                return interval > 0 ? (1.0 / interval).rounded() : 0
            },
            set: { advancedSettings.iconRefreshInterval = $0 > 0 ? 1.0 / $0 : 0 }
        )
        return LabeledContent {
            IceSlider(
                value: fpsBinding,
                in: 0 ... 30,
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
        .annotation("How often animated menu bar icons are refreshed in panels. Higher values are smoother but use more CPU.")
    }

    private var layoutBarsSection: some View {
        IceSection {
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
                    Text("Resets dividers and moves every movable item except the \(Constants.displayName) icon to hidden — just like a fresh install.")
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
                        Text("Reset Layout")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isResettingLayout || areControlItemsDisabledBySystem)
            }

            if let resetStatus {
                Text(resetStatus.message)
                    .font(.footnote)
                    .foregroundStyle(resetStatus.isError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .alert("Reset menu bar layout?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive) {
                resetMenuBarLayout()
            }
            Button("Cancel", role: .cancel) {
                isConfirmingReset = false
            }
        } message: {
            Text("Restores divider defaults and moves every movable item except the \(Constants.displayName) icon to Hidden. Use this if the layout looks broken or items won’t load.")
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

    private func resetMenuBarLayout() {
        isResettingLayout = true
        resetStatus = nil

        let manager = itemManager

        Task { @MainActor in
            do {
                let failedMoves = try await manager.resetLayoutToFreshState()
                if failedMoves == 0 {
                    resetStatus = .success
                } else {
                    resetStatus = .partialFailure(failedMoves)
                }
                isResettingLayout = false

                // cacheItemsRegardless + updateCacheWithoutChecks already run
                // inside resetLayoutToFreshState() — no need to repeat here.
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
        case success
        case partialFailure(Int)
        case failure(String)

        var message: String {
            switch self {
            case .success:
                String(localized: "Layout reset. Items were moved to the Hidden section.")
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
