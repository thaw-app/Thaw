//
//  MenuBarLayoutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import ThawCapture
import ThawUI

struct MenuBarLayoutSettingsPane: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    @State private var isHidingAvailable = true
    /// Why the out-of-reach warning's Relaunch did not happen, shown instead
    /// of a button that silently does nothing.
    @State private var relaunchErrorMessage: String?
    /// Set while macOS has Thaw itself switched off in its menu bar settings.
    @State private var isDeniedBySystem = false
    /// Refresh hidden occupancy from tags, not geometry, to avoid jitter; see MenuBarLayoutGroupsSection.
    @State private var isNothingHidden = false

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    /// Format warning names as a localized list with singular/plural sentences for subject agreement.
    private static func outOfReachMessage(for bundleIDs: Set<String>) -> LocalizedStringResource {
        let names = appNames(for: bundleIDs)
        return bundleIDs.count == 1
            ? "\(names) is running, but \(Constants.displayName) can't see its menu bar items, so it can't hide or arrange them. If its icon is missing from the menu bar too, quit and reopen \(names). Otherwise, relaunch \(Constants.displayName)."
            : "\(names) are running, but \(Constants.displayName) can't see their menu bar items, so it can't hide or arrange them. If their icons are missing from the menu bar too, quit and reopen them. Otherwise, relaunch \(Constants.displayName)."
    }

    private static func appNames(for bundleIDs: Set<String>) -> String {
        let names = bundleIDs.sorted().map { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first?.localizedName ?? bundleID
        }
        return names.formatted(.list(type: .and))
    }

    private var showsHideByDragHint: Bool {
        FirstRunHintStore.shared.isPending(.hideByDrag) && isNothingHidden
    }

    private func syncHiddenSectionOccupancy() {
        isNothingHidden = itemManager.managedItems(for: .hidden).isEmpty
            && itemManager.managedItems(for: .alwaysHidden).isEmpty
    }

    /// Show "hiding unsupported" only when the macOS 27 backend reports the visibility restriction unavailable.
    private var isHidingUnavailable: Bool {
        return !isHidingAvailable
    }

    private func syncHidingAvailability() {
        let controller = menuBarManager.sectionController
        // An absent engine does not prove hiding is unsupported; warn only for a running backend.
        isHidingAvailable = controller.isOperational ? controller.isHidingAvailable : true
    }

    var body: some View {
        let hasScreenRecordingPermission = ScreenCapture.hasCachedScreenRecordingPermission
        // Accessibility alone supports arrangement; without Screen Recording, use app icons as for failed crops.
        let canArrangeLayout = !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults

        // Full width on purpose: the item rows are the pane.
        ThawForm(readingWidth: .full) {
            if !canArrangeLayout {
                CannotArrangeLayoutView()
            } else {
                let banner = LayoutBanner.mostSerious(
                    isDeniedBySystem: isDeniedBySystem,
                    hasItemsOutOfReach: !itemManager.unseenHostBundleIDs.isEmpty,
                    hasScreenRecording: hasScreenRecordingPermission
                )
                switch banner {
                case .deniedBySystem:
                    ThawPlacementWarning(block: .deniedBySystem)
                case .outOfReach:
                    SettingsWarningPill(
                        title: "Some menu bar items are out of reach",
                        message: Self.outOfReachMessage(for: itemManager.unseenHostBundleIDs),
                        systemImage: "eye.trianglebadge.exclamationmark",
                        actionTitle: "Relaunch \(Constants.displayName)",
                        action: {
                            do {
                                try AppRelauncher.relaunch()
                            } catch {
                                relaunchErrorMessage = error.localizedDescription
                            }
                        }
                    )
                case .noScreenRecording:
                    SettingsWarningPill(
                        title: "Showing app icons",
                        message: "Add Screen Recording to see your real menu bar icons instead.",
                        systemImage: "eye.slash",
                        actionTitle: "Grant Access",
                        action: { appState.permissions.screenRecording.performRequest() }
                    )
                case nil:
                    EmptyView()
                }
                if LayoutBanner.allowsTips(beside: banner) {
                    LayoutMultiSelectTipView()
                    LayoutSuggestionCards(itemManager: itemManager)
                    if showsHideByDragHint {
                        ThawFirstRunHint(
                            systemImage: "hand.draw",
                            "Drag an icon into Hidden to tuck it away. Click \(Constants.displayName)'s icon in the menu bar to bring it back."
                        ) {
                            FirstRunHintStore.shared.dismiss(.hideByDrag)
                        }
                    }
                }
                LayoutBarsSection(itemManager: itemManager)
            }

            LayoutDetailTabs(
                itemManager: itemManager,
                canArrangeLayout: canArrangeLayout,
                isHidingUnavailable: isHidingUnavailable
            )
        }
        .thawAnimation(ThawMotion.settle, value: showsHideByDragHint)
        .errorAlert("Couldn’t relaunch \(Constants.displayName)", message: $relaunchErrorMessage)
        .modifier(
            HiddenSectionOccupancySync(itemManager: itemManager) {
                syncHiddenSectionOccupancy()
            }
        )
        .onAppear {
            syncHidingAvailability()
            appState.imageCache.loadFromDiskIfNeeded()
        }
        .task {
            guard let item = menuBarManager.controlItem(withName: .visible) else { return }
            for await block in item.$placementBlock.values {
                isDeniedBySystem = block == .deniedBySystem
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            menuBarManager.sectionController.refreshHidingAvailability()
            syncHidingAvailability()
        }
    }
}

/// Isolates membership-change observation here so tag updates do not re-diff the whole pane.
private struct HiddenSectionOccupancySync: ViewModifier {
    let itemManager: MenuBarItemManager
    let sync: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: itemManager.managedItemTags, initial: true) {
            sync()
        }
    }
}

/// The lists under the bars, one at a time: Options, Groups, Spacers and Apple's Items.
/// Search results switch to the tab that holds them.
private struct LayoutDetailTabs: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager
    let canArrangeLayout: Bool
    let isHidingUnavailable: Bool

    @State private var tab = LayoutDetailTab.options

    var body: some View {
        let settings = appState.settings.advanced
        // Groups and Apple's items need the bars, so without them only Options and Spacers are offered.
        let tabs = canArrangeLayout ? LayoutDetailTab.allCases : [.options, .spacers]
        SettingsPaneTabs(selection: $tab, tabs: tabs, tabForDisclosure: { LayoutDetailTab.tab(for: $0) })
        switch tabs.contains(tab) ? tab : .options {
        case .groups:
            MenuBarLayoutGroupsSection()
        case .spacers:
            ThawSection("Spacers") {
                LayoutSpacersRows(spacerManager: appState.spacerManager)
            }
        case .appleItems:
            ControlCenterReplacementsSection(settings: settings)
        case .options:
            LayoutSectionOptions(settings: settings, isHidingUnavailable: isHidingUnavailable)
            HidingMethodSection(settings: settings)
            LayoutOverflowSection(settings: settings)
            if canArrangeLayout {
                LayoutResetControls(
                    itemManager: itemManager,
                    controlItemsDisabled: itemManager.areControlItemsMissing,
                    alwaysHiddenEnabled: settings.enableAlwaysHiddenSection
                )
            }
        }
    }
}

private struct LayoutOverflowSection: View {
    @Bindable var settings: AdvancedSettings

    var body: some View {
        ThawSection("Overflow and previews") {
            Toggle(
                "Move items that don’t fit into Hidden",
                isOn: $settings.enableMenuBarItemOverflow
            )
            .annotation(
                "When the menu bar is full, move the Visible items that don’t fit into Hidden and open them from the \(Constants.displayName) Bar.",
                more: "Leave this off if you prefer macOS’s » button: macOS keeps the items that don’t fit there, and your layout stays exactly as you arranged it."
            )
            Toggle(
                "Use app icons instead of live previews",
                isOn: $settings.alwaysUseAppIconForMenuBarItems
            )
            .annotation(
                "Show each item's app icon in the Thaw Bar and Layout instead of a live screenshot.",
                more: "Turn this on if macOS's overflow arrow shows up in item previews. The real menu bar is unaffected."
            )
        }
    }
}

private struct LayoutSectionOptions: View {
    @Bindable var settings: AdvancedSettings
    let isHidingUnavailable: Bool

    var body: some View {
        ThawSection {
            Text("Sections")
        } content: {
            // Arrangement leads because it gates the section controls.
            ThawPillPicker(
                "Item arrangement",
                selection: $settings.menuBarArrangementMode,
                values: MenuBarArrangementMode.allCases,
                title: \.localized
            )
            .annotation(settings.menuBarArrangementMode.explanation)

            Toggle(
                "Always Hidden",
                isOn: $settings.enableAlwaysHiddenSection
            )
            .annotation("Adds a third section for items you rarely need. They stay out of sight when you show your Hidden items.")
            ThawPicker("Section divider style", selection: $settings.sectionDividerStyle) {
                ForEach(SectionDividerStyle.allCases) { style in
                    Text(style.localized).tag(style)
                }
            }
            if settings.sectionDividerStyle == .custom {
                CustomSectionDividerControls(settings: settings)
            }
        } footer: {
            if isHidingUnavailable {
                SettingsWarningPill(
                    title: "Hiding unavailable",
                    message: "This version of macOS doesn't let \(Constants.displayName) hide items. You can still reorder them in the bars above."
                )
            }
        }
    }
}

/// Spacer rows use a collapsed disclosure rather than a separate card because tuning is infrequent.
private struct LayoutSpacersRows: View {
    let spacerManager: MenuBarSpacerManager

    var body: some View {
        if let failure = spacerManager.lastPersistenceFailure {
            SettingsWarningPill(
                title: "Spacers weren’t saved",
                message: "\(failure) The spacers below are in the menu bar now, but they will not come back after a restart.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }

        ForEach(spacerManager.spacers) { spacer in
            LabeledContent {
                HStack(spacing: ThawSpacing.inset) {
                    ColorPicker(
                        "Spacer color",
                        selection: Binding(
                            get: { spacer.color.map { Color(cgColor: $0.cgColor) } ?? .clear },
                            set: { newColor in
                                spacerManager.setColor(NSColor(newColor).cgColor, for: spacer.id)
                            }
                        ),
                        supportsOpacity: true
                    )
                    .labelsHidden()
                    .help("Fill the spacer with a color. Fully transparent renders as an empty gap.")
                    ThawSlider(
                        value: Binding(
                            get: { Double(spacer.width) },
                            set: { spacerManager.setWidth(CGFloat($0), for: spacer.id) }
                        ),
                        in: Double(MenuBarSpacer.minWidth) ... Double(MenuBarSpacer.maxWidth),
                        step: 4
                    ) {
                        Text(verbatim: "\(Int(spacer.width)) pt")
                            .monospacedDigit()
                    }
                    Button {
                        spacerManager.removeSpacer(id: spacer.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Remove this spacer")
                    .accessibilityLabel("Remove this spacer")
                }
            } label: {
                Text("Spacer")
            }
        }

        Button("Add Spacer") {
            spacerManager.addSpacer()
        }
        .buttonStyle(.settingsGlass)
        .annotation(
            "Inserts an empty gap item into the menu bar.",
            more: "To move it, hold ⌘ Command and drag it in the menu bar, like any other item."
        )
    }
}
