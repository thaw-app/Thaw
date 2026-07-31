//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawCapture

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager
    @State private var isHidingAvailable = true

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    /// Whether to show the "hiding unsupported" warning: only relevant on
    /// macOS 27+ (where `sectionController` exists) and only when its backend
    /// reports the private Assessment Mode API is unavailable.
    private var isHidingUnavailable: Bool {
        guard #available(macOS 27, *) else { return false }
        return !isHidingAvailable
    }

    private func syncHidingAvailability() {
        isHidingAvailable = menuBarManager.sectionController?.isHidingAvailable ?? true
    }

    var body: some View {
        let hasScreenRecordingPermission = ScreenCapture.hasCachedScreenRecordingPermission
        let canArrangeLayout = hasScreenRecordingPermission
            && !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults

        IceForm {
            if !hasScreenRecordingPermission {
                MissingLayoutPermissionView()
            } else if !canArrangeLayout {
                CannotArrangeLayoutView()
            } else {
                LayoutBarsSection(itemManager: itemManager)
            }

            if canArrangeLayout {
                MenuBarLayoutGroupsSection()
            }

            LayoutSectionOptions(
                settings: appState.settings.advanced,
                isHidingUnavailable: isHidingUnavailable
            )
            LayoutIconPreviewControls(settings: appState.settings.advanced)

            if canArrangeLayout {
                if #available(macOS 27, *) {
                    LayoutSystemItemControl(isEnabled: systemItemHidingBinding)
                }
            }

            LayoutAdvancedControls(
                settings: appState.settings.advanced,
                navigationState: appState.navigationState
            )

            if canArrangeLayout {
                LayoutResetControls(
                    itemManager: itemManager,
                    controlItemsDisabled: itemManager.areControlItemsMissing,
                    alwaysHiddenEnabled: appState.settings.advanced.enableAlwaysHiddenSection
                )
            }
        }
        .onAppear {
            appState.imageCache.markSettingsPaneOpened()
            syncHidingAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            menuBarManager.sectionController?.refreshHidingAvailability()
            syncHidingAvailability()
        }
    }

    private var systemItemHidingBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.advanced.enableExperimentalSystemItemHiding },
            set: { newValue in
                appState.settings.advanced.enableExperimentalSystemItemHiding = newValue
                appState.menuBarManager.sectionController?.refresh()
            }
        )
    }
}

struct LayoutIconPreviewControls: View {
    @ObservedObject var settings: AdvancedSettings
    @State private var labelWidth: CGFloat = 0

    private var fpsBinding: Binding<Double> {
        Binding(
            get: {
                let interval = settings.iconRefreshInterval
                return interval > 0 ? (1.0 / interval).rounded() : 0
            },
            set: { settings.iconRefreshInterval = $0 > 0 ? 1.0 / $0 : 0 }
        )
    }

    var body: some View {
        IceSection("Icon previews") {
            LabeledContent {
                IceSlider(value: fpsBinding, in: 0 ... 30, step: 1) {
                    Text(fpsBinding.wrappedValue > 0 ? "\(Int(fpsBinding.wrappedValue)) fps" : "Off")
                }
            } label: {
                Text("Icon refresh rate")
                    .frame(minWidth: labelWidth, alignment: .leading)
                    .onFrameChange { frame in
                        labelWidth = max(labelWidth, frame.width)
                    }
            }
            .annotation("How often animated menu bar icons are refreshed in panels. Higher values are smoother but use more CPU.")
        }
    }
}

private struct LayoutSectionOptions: View {
    @ObservedObject var settings: AdvancedSettings
    let isHidingUnavailable: Bool

    var body: some View {
        IceSection("Sections") {
            if isHidingUnavailable {
                SettingsWarningPill(
                    title: "Hiding unavailable",
                    message: "This macOS build is missing the system capability Thaw needs to hide items. Reordering still works; hiding does not."
                )
            }
            Toggle(
                "Enable the always-hidden section",
                isOn: $settings.enableAlwaysHiddenSection
            )
            IcePicker("Section divider style", selection: $settings.sectionDividerStyle) {
                ForEach(SectionDividerStyle.allCases) { style in
                    Text(style.localized).tag(style)
                }
            }
        }
    }
}

private struct LayoutBarsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager
    @State private var loadDeadlineReached = false

    private let diagLog = DiagLog(category: "MenuBarLayoutPane")

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    var body: some View {
        IceSection {
            Text("Arrange menu bar items")
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drag items between sections. Move New Items to choose where future items appear.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Tip: Hold ⌘ Command while dragging an item directly in the menu bar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // A refused group move snaps back with no other explanation, so
                // the reason appears here rather than in a modal that would
                // cover the very bars the user is arranging.
                if let refusal = appState.layoutFeedback.refusal {
                    SettingsWarningPill(
                        title: LocalizedStringKey(refusal.title),
                        message: LocalizedStringKey(refusal.message),
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange,
                        actionTitle: "Dismiss"
                    ) {
                        appState.layoutFeedback.clear()
                    }
                    .transition(reduceMotion ? .identity : .opacity)
                }

                VStack(spacing: 20) {
                    ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                        if let menuBarSection = appState.menuBarManager.section(withName: section), menuBarSection.isEnabled {
                            VStack(alignment: .leading) {
                                Text(section.localized)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                                LayoutBar(imageCache: appState.imageCache, section: section)
                            }
                        }
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18)) { content in
                    content.opacity(hasItems ? 1 : 0.75)
                }
                .allowsHitTesting(hasItems)
                .overlay {
                    if !hasItems {
                        loadingOverlay
                            .transition(layoutTransition)
                    }
                }
            }
        }
        .task(id: hasItems) {
            await loadItemsIfNeeded()
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 8) {
            if loadDeadlineReached {
                VStack(spacing: 4) {
                    if itemManager.areControlItemsMissing {
                        Text("One or more section dividers are hidden by macOS")
                        Text("Check System Settings > Menu Bar and enable \(Constants.displayName)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Unable to load menu bar items")
                    }
                }
                .transition(layoutTransition)
            } else {
                VStack(spacing: 8) {
                    Text("Loading menu bar items…")
                    ProgressView()
                }
                .transition(layoutTransition)
            }
        }
    }

    private var layoutTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.animation(.easeOut(duration: 0.18))
    }

    private func loadItemsIfNeeded() async {
        loadDeadlineReached = false
        guard !hasItems, ScreenCapture.hasCachedScreenRecordingPermission else { return }

        diagLog.debug("Preloading menu bar layout caches (hasItems=\(self.hasItems), screenRecording=\(ScreenCapture.hasCachedScreenRecordingPermission))")
        async let preloadCaches: Void = preloadLayoutCaches()
        try? await Task.sleep(for: .seconds(3))

        if !Task.isCancelled, !hasItems {
            loadDeadlineReached = true
            diagLog.error("Menu bar layout failed to load items after 3s timeout. cacheItems: \(itemManager.itemCache.managedItems.count), images: \(appState.imageCache.images.count), displayID: \(self.itemManager.itemCache.displayID.map { "\($0)" } ?? "nil")")
        }
        await preloadCaches
    }

    private func preloadLayoutCaches() async {
        await itemManager.cacheItemsRegardless(skipRecentMoveCheck: true)
        guard !Task.isCancelled else { return }

        if #available(macOS 27, *) {
            // Fill gaps only so opening Layout cannot overwrite settled
            // Hidden glyphs with native overflow chevron («») crops.
            await appState.imageCache.prewarmConcealedImagesMacOS27(
                sections: [.hidden, .alwaysHidden],
                onlyMissingImages: true
            )
            guard !Task.isCancelled else { return }
        }

        await appState.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
    }
}

@available(macOS 27, *)
private struct LayoutSystemItemControl: View {
    @Binding var isEnabled: Bool

    var body: some View {
        IceSection {
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow hiding macOS system items")
                    Text("Allows items such as Clock, Control Center, and Siri to be moved into hidden sections.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Note: When Thaw Bar is off, hidden Clock, Control Center, and Siri stay anchored at the right side of the layout. You can still change whether they are visible or hidden.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LayoutAdvancedControls: View {
    @ObservedObject var settings: AdvancedSettings
    @ObservedObject var navigationState: AppNavigationState
    @State private var isExpanded = false

    var body: some View {
        // Disclosure as a form row (Hotkeys pattern) — not nested mini-sections
        // inside the card, which read as double chrome.
        IceSection {
            DisclosureGroup("Advanced layout controls", isExpanded: $isExpanded) {
                Toggle(
                    "Move items that don't fit into Hidden",
                    isOn: $settings.enableMenuBarItemOverflow
                )
                .annotation(
                    "Move menu bar items from Visible into Hidden when they don't fit beside the notch. Disable to keep the saved profile layout exactly as authored."
                )

                Toggle(
                    "Use LCS sorting on notched displays",
                    isOn: $settings.useLCSSortingOnNotchedDisplays
                )
                .annotation(
                    "Use the faster LCS algorithm for profile sorting on notched displays. It minimises moves but may be less reliable at smaller resolutions."
                )

                if #available(macOS 27, *) {
                    Toggle(
                        "Use app icons instead of live previews",
                        isOn: $settings.alwaysUseAppIconForMenuBarItems
                    )
                    .annotation(
                        "Show each item's app icon in the Thaw Bar and layout editor instead of a live screenshot. Use this if macOS 27's native overflow control bleeds into the captured previews. The real menu bar is unaffected."
                    )

                    LabeledContent("Reorder timeout") {
                        IceSlider(value: $settings.menuBarOrderFulfillmentTimeout, in: 1 ... 15, step: 0.5) {
                            SecondsLabel(value: settings.menuBarOrderFulfillmentTimeout)
                        }
                    }
                    .annotation("How long Thaw waits for macOS to apply a menu bar reorder before continuing with any remaining layout work.")
                }
            }
        }
        .onChange(of: navigationState.requestedSettingsDisclosure, initial: true) { _, _ in
            guard SettingsSearchNavigation.consumeDisclosure(
                .advancedLayoutControls,
                navigationState: navigationState
            ) else { return }
            isExpanded = true
        }
    }
}

private struct LayoutResetControls: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var itemManager: MenuBarItemManager
    let controlItemsDisabled: Bool
    let alwaysHiddenEnabled: Bool

    @State private var isResetting = false
    @State private var isConfirming = false
    @State private var status: ResetStatus?

    var body: some View {
        IceSection {
            Text("Reset menu bar layout")
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text("Moves every movable item except the \(Constants.displayName) icon to the selected section — just like a fresh install.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Button {
                        isConfirming = true
                    } label: {
                        if isResetting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Reset Layout…")
                        }
                    }
                    .buttonStyle(.settingsGlass)
                    .disabled(isResetting || controlItemsDisabled)
                }

                if isConfirming {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose where to move the menu bar items:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Visible") { reset(to: .visible) }
                            Button("Hidden") { reset(to: .hidden) }
                            if alwaysHiddenEnabled {
                                Button("Always Hidden") { reset(to: .alwaysHidden) }
                            }
                            Button("Cancel", role: .cancel) { isConfirming = false }
                        }
                        .buttonStyle(.settingsGlass)
                    }
                    .transition(resetTransition)
                }

                if let status {
                    Text(status.message)
                        .font(.footnote)
                        .foregroundStyle(status.isError ? .red : .secondary)
                        .transition(resetTransition)
                }
            }
        }
    }

    private var resetTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.animation(.easeOut(duration: 0.18))
    }

    private func reset(to target: ResetTarget) {
        isConfirming = false
        isResetting = true
        status = nil

        Task { @MainActor in
            do {
                let failures = switch target {
                case .visible: try await itemManager.resetLayoutToVisible()
                case .hidden: try await itemManager.resetLayoutToFreshState()
                case .alwaysHidden: try await itemManager.resetLayoutToAlwaysHidden()
                }
                let newStatus: ResetStatus = failures == 0 ? .success(target) : .partialFailure(failures)
                status = newStatus
                AccessibilityAnnouncements.post(newStatus.message)
            } catch {
                status = .failure(error.localizedDescription)
            }
            isResetting = false
        }
    }

    private enum ResetTarget {
        case visible
        case hidden
        case alwaysHidden
    }

    private enum ResetStatus {
        case success(ResetTarget)
        case partialFailure(Int)
        case failure(String)

        var message: String {
            switch self {
            case .success(.hidden): String(localized: "Layout reset. Items were moved to the Hidden section.")
            case .success(.alwaysHidden): String(localized: "Layout reset. Items were moved to the Always Hidden section.")
            case .success(.visible): String(localized: "Items were moved to the Visible section.")
            case let .partialFailure(count): String(localized: "Reset completed with \(count) items that could not be moved. Check the menu bar and try again if needed.")
            case let .failure(message): String(localized: "Reset failed: \(message)")
            }
        }

        var isError: Bool {
            switch self {
            case .success: false
            case .partialFailure, .failure: true
            }
        }
    }
}

private struct CannotArrangeLayoutView: View {
    var body: some View {
        Text("\(Constants.displayName) cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MissingLayoutPermissionView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack {
            Text("Menu bar layout requires screen recording permissions.")
                .font(.title2)
            Button("Go to Advanced Settings") {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            }
            .buttonStyle(.link)
        }
    }
}
