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

    @State private var loadDeadlineReached = false
    @State private var isResettingLayout = false
    @State private var resetStatus: ResetStatus?
    @State private var isConfirmingReset = false

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
            IceForm(spacing: 20) {
                header
                layoutBars
                if #available(macOS 27, *) {
                    systemItemHidingControls
                    experimentalOverflowPreventionControl
                    // Experimental window hiding disabled — plist-based per-item
                    // hiding does not work on macOS 27 (removing keys from
                    // TrailingItemPreferredPositions does not hide items).
                    // experimentalWindowHidingControls
                }
                resetControls
            }
            .onAppear {
                // Enable background cache prewarming now that the user has opened
                // the layout settings pane at least once.
                appState.imageCache.markSettingsPaneOpened()
            }
        }
    }

    private var header: some View {
        IceSection {
            headerIntro
        }
    }

    private var headerIntro: some View {
        VStack(spacing: 3) {
            Text("Drag to arrange your menu bar items into different sections.")
                .font(.title3.bold())
            Text("Move the New Items badge to choose where newly detected items will appear.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        // Native Form rows are leading-aligned; keep this intro centered.
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var layoutBars: some View {
        VStack(spacing: 20) {
            if #available(macOS 27, *) {
                nonHideableItemsNotice
            }
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
                                    .font(.calloutBox)
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

    /// On macOS 27 the anchored modules hosted by `com.apple.MenuBarAgent`
    /// (Control Center and the Clock) can't be concealed by the visibility
    /// assertion, so they stay in Visible and can't be dragged to Hidden. Other
    /// MenuBarAgent modules (Wi-Fi, Bluetooth, AirDrop, Sound…) *are* hideable
    /// through Control Center, so they're deliberately not named here. Warn the
    /// user so a stuck item doesn't read as a bug.
    @available(macOS 27, *)
    private var nonHideableItemsNotice: some View {
        SettingsWarningPill(
            message: "On macOS 27, some items can be reordered but not yet hidden. Native macOS items such as Clock, Control Center, and Siri stay visible unless system item hiding is enabled, and a few MenuBarAgent modules — like AirDrop and Sound — may also be restricted. Apps on Thaw's hiding denylist share the same restriction. You can still rearrange them in the Visible section."
        )
    }

    @available(macOS 27, *)
    private var systemItemHidingControls: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: systemItemHidingBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide macOS system items")
                            .font(.headline)
                        Text("Allows items such as Clock, Control Center, and Siri to be moved into hidden sections.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Note: When Thaw Bar is off, hidden Clock, Control Center, and Siri stay anchored at the right side of the layout. You can still change whether they are visible or hidden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var systemItemHidingBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.advanced.enableExperimentalSystemItemHiding },
            set: { newValue in
                appState.settings.advanced.enableExperimentalSystemItemHiding = newValue
                appState.menuBarManager.simpleItemHider?.refresh()
            }
        )
    }

    @available(macOS 27, *)
    private var experimentalWindowHidingControls: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: experimentalWindowHidingBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hide third-party items off-screen (experimental)")
                            .font(.headline)
                        Text("Hides app items by moving their windows off-screen instead of using the system restriction, so hiding one item no longer makes dynamic neighbors like iStat Menus flicker or disappear.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsWarningPill(
                    message: "This is experimental and uses private window APIs. Hidden items are restored when Thaw quits."
                )
            }
        }
    }

    @available(macOS 27, *)
    private var experimentalOverflowPreventionControl: some View {
        IceSection {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: experimentalOverflowPreventionBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prevent native menu bar overflow hiding (experimental)")
                            .font(.headline)
                        Text("On notched displays, macOS may collapse items behind a chevron when the menu bar is full. This writes hidden items' position weights to extreme values so the native overflow collapses them first, keeping visible items on screen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsWarningPill(
                    message: "Experimental. May cause layout issues on some setups. Only affects macOS 27+ notched displays."
                )
            }
        }
    }

    private var experimentalOverflowPreventionBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.advanced.enableExperimentalOverflowPrevention },
            set: { newValue in
                appState.settings.advanced.enableExperimentalOverflowPrevention = newValue
                appState.menuBarManager.simpleItemHider?.refresh()
            }
        )
    }

    private var experimentalWindowHidingBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.advanced.enableExperimentalWindowHiding },
            set: { newValue in
                appState.settings.advanced.enableExperimentalWindowHiding = newValue
                appState.menuBarManager.simpleItemHider?.refresh()
            }
        )
    }

    private var resetControls: some View {
        IceSection(options: [.isBordered]) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reset menu bar layout")
                            .font(.headline)
                        Text("Moves every movable item except the \(Constants.displayName) icon to the selected section — just like a fresh install.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

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

                if let resetStatus {
                    Text(resetStatus.message)
                        .font(.footnote)
                        .foregroundStyle(resetStatus.isError ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .confirmationDialog("Reset to…", isPresented: $isConfirmingReset) {
            Button("Reset to Visible") { resetMenuBarLayout(to: .visible) }
            Button("Reset to Hidden") { resetMenuBarLayout(to: .hidden) }
            if appState.settings.advanced.enableAlwaysHiddenSection {
                Button("Reset to Always Hidden") { resetMenuBarLayout(to: .alwaysHidden) }
            }
            Button("Cancel", role: .cancel) {
                isConfirmingReset = false
            }
        } message: {
            Text("Moves every movable item except the \(Constants.displayName) icon to the chosen section.")
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

    private var loadingMenuBarItems: some View {
        VStack {
            Text("Loading menu bar items…")
            ProgressView()
        }
        .font(.title)
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

    private enum ResetTarget {
        case visible
        case hidden
        case alwaysHidden
    }

    private func resetMenuBarLayout(to target: ResetTarget) {
        isResettingLayout = true
        resetStatus = nil

        let manager = itemManager

        Task { @MainActor in
            do {
                let failedMoves = switch target {
                case .hidden:
                    try await manager.resetLayoutToFreshState()
                case .visible:
                    try await manager.resetLayoutToVisible()
                case .alwaysHidden:
                    try await manager.resetLayoutToAlwaysHidden()
                }
                if failedMoves == 0 {
                    resetStatus = switch target {
                    case .hidden:
                        .successToHidden
                    case .alwaysHidden:
                        .successToAlwaysHidden
                    case .visible:
                        .successToVisible
                    }
                } else {
                    resetStatus = .partialFailure(failedMoves)
                }
                isResettingLayout = false
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
        case successToHidden
        case successToAlwaysHidden
        case successToVisible
        case partialFailure(Int)
        case failure(String)

        var message: String {
            switch self {
            case .successToHidden:
                String(localized: "Layout reset. Items were moved to the Hidden section.")
            case .successToAlwaysHidden:
                String(localized: "Layout reset. Items were moved to the Always Hidden section.")
            case .successToVisible:
                String(localized: "Items were moved to the Visible section.")
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
            case .successToHidden, .successToAlwaysHidden, .successToVisible:
                false
            }
        }
    }
}
