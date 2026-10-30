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
    private static func outOfReachMessage(for bundleIDs: Set<String>) -> LocalizedStringKey {
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
            HidingMethodSection(settings: settings, offersAppleItems: canArrangeLayout)
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
                HStack(spacing: 12) {
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

struct LayoutBarsSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager

    var body: some View {
        // A header avoids row clipping 20pt below the card's top edge; no rows means no card obscuring the first bar.
        Section {
            EmptyView()
        } header: {
            FoldedMenuBar(itemManager: itemManager, arrangement: .spaced)
                .textCase(nil)
                .font(nil)
                .foregroundStyle(.primary)
                // Grouped Form rows stop growing at a fixed width; size from the scroll view less the Form's 20pt insets, but never set the Form's minimum.
                .containerRelativeFrame(.horizontal) { width, _ in width - 40 }.frame(minWidth: 0, maxWidth: .infinity)
        } footer: {
            HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.base) {
                Text("Drag items between sections. Hold ⌘ Command to drag in the menu bar.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ThawSpacing.base)
                if showsPopOutButton {
                    popOutButton
                }
            }
        }

        layoutRefusalNotice
    }

    /// Not inside the pop-out itself.
    private var showsPopOutButton: Bool {
        !appState.navigationState.isLayoutEditorPresented
    }

    private var popOutButton: some View {
        Button("Pop Out Editor", systemImage: "rectangle.portrait.and.arrow.right") {
            guard let screen = MenuBarLayoutEditorPanel.defaultScreen else { return }
            let menuBarManager = appState.menuBarManager
            menuBarManager.layoutEditorPanel.show(on: screen, usesReorderEditor: true) {
                menuBarManager.dismissLayoutEditorPanel()
            }
        }
        .buttonStyle(.settingsGlass)
        .help("Opens the experimental reorder editor in its own window.")
    }

    /// A refused group move snaps back with no other explanation, so the
    /// reason appears here rather than in a modal that would cover the bars.
    @ViewBuilder
    private var layoutRefusalNotice: some View {
        if let refusal = appState.layoutFeedback.refusal {
            VStack(alignment: .leading, spacing: 12) {
                Text("macOS 27 does not let \(Constants.displayName) hide some system items.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsWarningPill(
                    title: LocalizedStringKey(refusal.title),
                    message: LocalizedStringKey(refusal.message),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange,
                    actionTitle: "Dismiss"
                ) {
                    appState.layoutFeedback.clear()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(reduceMotion ? .identity : .opacity)
        }
    }
}

struct LayoutResetControls: View {
    let itemManager: MenuBarItemManager
    let controlItemsDisabled: Bool
    let alwaysHiddenEnabled: Bool

    var body: some View {
        ThawSection {
            Text("Reset menu bar layout")
        } content: {
            LayoutResetFlow(
                itemManager: itemManager,
                controlItemsDisabled: controlItemsDisabled,
                alwaysHiddenEnabled: alwaysHiddenEnabled
            )
        }
    }
}

/// Reset, in its titled section: a sentence beside a glass button.
struct LayoutResetFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let itemManager: MenuBarItemManager
    let controlItemsDisabled: Bool
    let alwaysHiddenEnabled: Bool

    @State private var isResetting = false
    @State private var isConfirming = false
    @State private var status: ResetStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("Moves every movable item except the \(Constants.displayName) icon to the selected section, just like a fresh install.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                Spacer(minLength: 16)
                trigger
                    .disabled(isResetting || controlItemsDisabled)
            }

            if let status {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if status.isError {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    Text(status.message)
                        .foregroundStyle(status.isError ? Color.primary : ThawInk.supporting)
                }
                .font(ThawType.footnote)
                .transition(resetTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Choose where to move the menu bar items:",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Visible") { reset(to: .visible) }
            Button("Hidden") { reset(to: .hidden) }
            if alwaysHiddenEnabled {
                Button("Always Hidden") { reset(to: .alwaysHidden) }
            }
            Button("Cancel", role: .cancel) { /* The dialog dismisses itself; cancelling needs no other work. */ }
        }
    }

    private var trigger: some View {
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
    }

    private var resetTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.animation(ThawMotion.settle)
    }

    private func reset(to target: ResetTarget) {
        isConfirming = false
        isResetting = true
        status = nil

        Task { @MainActor in
            let newStatus: ResetStatus
            do {
                let failures = switch target {
                case .visible: try await itemManager.resetLayoutToVisible()
                case .hidden: try await itemManager.resetLayoutToFreshState()
                case .alwaysHidden: try await itemManager.resetLayoutToAlwaysHidden()
                }
                newStatus = .completed(target: target, failures: failures)
            } catch {
                newStatus = .thrown(error)
            }
            status = newStatus
            if newStatus.isAnnounced {
                AccessibilityAnnouncements.post(newStatus.message)
            }
            isResetting = false
        }
    }

    /// Internal for tests that prevent untouched menu bars from being reported as reset.
    enum ResetTarget: Equatable {
        case visible
        case hidden
        case alwaysHidden
    }

    enum ResetStatus: Equatable {
        case success(ResetTarget)
        /// The reset never started: the menu bar backend is not running, so
        /// nothing was moved and there is nothing to check.
        case notRun
        case partialFailure(Int)
        case failure(String)

        /// Zero failed moves means success only for resets that ran; unstarted resets must not reach here.
        static func completed(target: ResetTarget, failures: Int) -> ResetStatus {
            failures == 0 ? .success(target) : .partialFailure(failures)
        }

        /// engineNotRunning means no attempt, not a failed sweep; report notRun rather than claiming items moved.
        static func thrown(_ error: any Error) -> ResetStatus {
            if case .engineNotRunning? = error as? MenuBarItemManager.LayoutResetError {
                return .notRun
            }
            return .failure(error.localizedDescription)
        }

        /// Announce completion outcomes for VoiceOver; underlying failure text is displayed but not spoken.
        var isAnnounced: Bool {
            switch self {
            case .success, .notRun, .partialFailure: true
            case .failure: false
            }
        }

        var message: String {
            switch self {
            case .success(.hidden): String(localized: "Layout reset. Items were moved to the Hidden section.")
            case .success(.alwaysHidden): String(localized: "Layout reset. Items were moved to the Always Hidden section.")
            case .success(.visible): String(localized: "Items were moved to the Visible section.")
            case .notRun: String(localized: "Nothing was moved: \(Constants.displayName) is not managing the menu bar yet. Try again once your menu bar items appear.")
            case let .partialFailure(count): String(localized: "Reset completed with \(count) items that could not be moved. Check the menu bar and try again if needed.")
            case let .failure(message): String(localized: "Reset failed: \(message)")
            }
        }

        var isError: Bool {
            switch self {
            case .success: false
            case .notRun, .partialFailure, .failure: true
            }
        }
    }
}

/// Shown instead of the editor while macOS auto-hides the menu bar.
struct CannotArrangeLayoutView: View {
    var body: some View {
        ThawEmptyState(
            systemImage: "menubar.rectangle",
            title: "\(Constants.displayName) cannot arrange menu bar items in automatically hidden menu bars.",
            caption: "Turn off automatic menu bar hiding in System Settings > Control Center"
        )
    }
}

/// Isolate notch-suggestion cache reads to avoid re-diffing the whole form.
private struct LayoutSuggestionCards: View {
    @Environment(AppState.self) private var appState
    let itemManager: MenuBarItemManager

    /// Bumped on dismissal, so a card disappears at once.
    @State private var dismissals = 0

    private var visibleItems: [MenuBarItem] {
        itemManager.managedItems(for: .visible)
    }

    // Hints suggest improvements, not failures; closing means "Not now" and suppresses them for a month.
    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = dismissals
        let behindNotch = LayoutSuggestions.itemsBehindNotch(visibleItems, notchRects: MenuBarNotchGeometry.rects)
        if !behindNotch.isEmpty, !LayoutSuggestionDismissal.isQuiet(.itemsBehindNotch) {
            ThawFirstRunHint(
                systemImage: "rectangle.topthird.inset.filled",
                behindNotch.count == 1
                    ? "\(LayoutSuggestions.names(of: behindNotch)) is behind the notch. Move it to Hidden and it opens from the \(Constants.displayName) Bar instead."
                    : "\(LayoutSuggestions.names(of: behindNotch)) are behind the notch. Move them to Hidden and they open from the \(Constants.displayName) Bar instead.",
                actionTitle: "Move to Hidden",
                action: { MenuBarSearchItemActions.move(behindNotch, to: .hidden, appState: appState) },
                onDismiss: { dismiss(.itemsBehindNotch) }
            )
        }
        if littleSnitchItemIsMissing, !LayoutSuggestionDismissal.isQuiet(.littleSnitchScriptingAccess) {
            ThawFirstRunHint(
                systemImage: "exclamationmark.triangle",
                "Little Snitch is running, but \(Constants.displayName) can’t see its menu bar icon. In Little Snitch’s settings, under Security, turn on “Allow GUI Scripting access to Little Snitch.”",
                actionTitle: "Open Little Snitch",
                action: openLittleSnitch,
                onDismiss: { dismiss(.littleSnitchScriptingAccess) }
            )
        }
    }

    private var littleSnitchItemIsMissing: Bool {
        LayoutSuggestions.littleSnitchItemIsMissing(
            runningBundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            items: itemManager.managedItems
        )
    }

    private func openLittleSnitch() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: LayoutSuggestions.littleSnitchAppBundleID
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func dismiss(_ kind: LayoutSuggestionDismissal.Kind) {
        LayoutSuggestionDismissal.dismiss(kind)
        dismissals += 1
    }
}
