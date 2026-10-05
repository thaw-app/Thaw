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

    /// Refresh hidden occupancy from tags, not geometry, to avoid jitter; see MenuBarLayoutGroupsSection.
    @State private var isNothingHidden = false

    /// The macOS 27 limitations list opens on the first visit to this pane and
    /// leaves only its info button once acknowledged.
    @State private var isLimitationsAcknowledged = Defaults.bool(forKey: .platformLimitationsAcknowledged)

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    /// Format warning names as a localized list with singular/plural sentences for subject agreement.
    private static func outOfReachMessage(for bundleIDs: Set<String>) -> LocalizedStringKey {
        let names = appNames(for: bundleIDs)
        return bundleIDs.count == 1
            ? "\(names) is running, but \(Constants.displayName) can't see its menu bar items, so it can't hide or arrange them. Relaunching \(Constants.displayName) fixes this."
            : "\(names) are running, but \(Constants.displayName) can't see their menu bar items, so it can't hide or arrange them. Relaunching \(Constants.displayName) fixes this."
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
                PlatformLimitationsNotice(
                    isAcknowledged: isLimitationsAcknowledged,
                    onAcknowledge: {
                        Defaults.set(true, forKey: .platformLimitationsAcknowledged)
                        isLimitationsAcknowledged = true
                    }
                )
                if !hasScreenRecordingPermission {
                    SettingsWarningPill(
                        title: "Showing app icons",
                        message: "Add Screen Recording to see your real menu bar icons instead.",
                        systemImage: "eye.slash",
                        actionTitle: "Grant Access",
                        action: { appState.permissions.screenRecording.performRequest() }
                    )
                }
                if !itemManager.unseenHostBundleIDs.isEmpty {
                    SettingsWarningPill(
                        title: "Some menu bar items are out of reach",
                        message: Self.outOfReachMessage(for: itemManager.unseenHostBundleIDs),
                        systemImage: "eye.trianglebadge.exclamationmark",
                        actionTitle: "Relaunch",
                        action: {
                            do {
                                try AppRelauncher.relaunch()
                            } catch {
                                relaunchErrorMessage = error.localizedDescription
                            }
                        }
                    )
                }
                LayoutSuggestionCards(itemManager: itemManager)
                if showsHideByDragHint {
                    ThawFirstRunHint(
                        systemImage: "hand.draw",
                        "Drag an icon into Hidden to tuck it away. Click \(Constants.displayName)'s icon in the menu bar to bring it back."
                    ) {
                        FirstRunHintStore.shared.dismiss(.hideByDrag)
                    }
                }
                LayoutBarsSection(itemManager: itemManager)
            }

            if canArrangeLayout {
                MenuBarLayoutGroupsSection()
            }

            LayoutSectionOptions(
                settings: appState.settings.advanced,
                isHidingUnavailable: isHidingUnavailable
            )

            if canArrangeLayout {
                LayoutSystemItemControl(isEnabled: systemItemHidingBinding)
                LayoutUnshowableItemControls(
                    general: appState.settings.general,
                    advanced: appState.settings.advanced
                )
            }

            LayoutMoreOptionsSection(
                spacerManager: appState.spacerManager,
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            menuBarManager.sectionController.refreshHidingAvailability()
            syncHidingAvailability()
        }
    }

    private var systemItemHidingBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.advanced.enableExperimentalSystemItemHiding },
            set: { newValue in
                appState.settings.advanced.enableExperimentalSystemItemHiding = newValue
                appState.menuBarManager.sectionController.refresh()
            }
        )
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

/// Keep infrequently changed options in one card below the drag editor.
/// Only Spacers collapses because its rows grow; single-row options stay open without nested disclosures.
private struct LayoutMoreOptionsSection: View {
    let spacerManager: MenuBarSpacerManager
    @Bindable var settings: AdvancedSettings
    let navigationState: AppNavigationState

    @State private var isSpacersExpanded = false

    var body: some View {
        ThawSection("More layout options") {
            DisclosureGroup("Spacers", isExpanded: $isSpacersExpanded) {
                LayoutSpacersRows(spacerManager: spacerManager)
            }

            Toggle(
                "Move items that don’t fit into Hidden",
                isOn: $settings.enableMenuBarItemOverflow
            )
            .annotation(
                "When the menu bar is full, move the Visible items that don’t fit into Hidden, so they stay reachable instead of going behind macOS’s » button.",
                more: "Turn this off to keep the saved profile layout exactly as you arranged it."
            )

            Toggle(
                "Use app icons instead of live previews",
                isOn: $settings.alwaysUseAppIconForMenuBarItems
            )
            .annotation(
                "Show each item's app icon in the Thaw Bar and Layout instead of a live screenshot.",
                more: "Turn this on if macOS's overflow arrow shows up in item previews. The real menu bar is unaffected."
            )

            // Hide reorder timeout until it has an effect; macOS 27's early-bail probe ends the wait first.
//            LabeledContent("Reorder timeout") {
//                ThawSlider(value: $settings.menuBarOrderFulfillmentTimeout, in: 1 ... 15, step: 0.5) {
//                    SecondsLabel(value: $settings.menuBarOrderFulfillmentTimeout)
//                }
//            }
//            .annotation("How long Thaw waits for macOS to apply a menu bar reorder before continuing with any remaining layout work.")
        }
        // Expand Spacers for search deep-links so the target is reachable.
        .onChange(of: navigationState.requestedSettingsDisclosure, initial: true) { _, _ in
            if SettingsSearchNavigation.consumeDisclosure(
                .layoutSpacers,
                navigationState: navigationState
            ) {
                isSpacersExpanded = true
            }
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
            ThawPicker("Item arrangement", selection: $settings.menuBarArrangementMode) {
                ForEach(MenuBarArrangementMode.allCases) { mode in
                    Text(mode.localized).tag(mode)
                }
            }
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

/// The drag-and-drop icon editor. Not private: Simple Mode presents this same
/// editor as its whole screen.
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
                // Offset the header inset so bars match the surrounding card width.
                .padding(.horizontal, -10)
        } footer: {
            Text("Drag items between sections. Hold ⌘ Command to drag in the menu bar.")
                .font(ThawType.footnote)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)
        }

        layoutRefusalNotice
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

/// macOS 27 hosts Apple items through a fragile move path; keep the explanation reachable behind the info button without crowding the row.
/// Name affected items because "system items" can be mistaken for only Clock and Control Center.
private struct LayoutSystemItemControl: View {
    @Binding var isEnabled: Bool

    var body: some View {
        ThawSection {
            Toggle("Allow hiding Apple’s own menu bar items", isOn: $isEnabled)
                .annotation(
                    "Covers the items macOS pins to the right: Clock, Control Center and Siri.",
                    more: "Other built-in items are managed separately, and third-party items can always be hidden.\n\nWhile the Thaw Bar is off, hidden Clock, Control Center and Siri stay pinned to the right side of the layout. You can still switch them between visible and hidden."
                )

            disclaimer
        }
    }

    /// Warn about the unreliable route only when enabled; blue denotes a limitation, not a failure.
    @ViewBuilder
    private var disclaimer: some View {
        if isEnabled {
            SettingsWarningPill(
                title: "Apple's items move differently",
                message: "macOS 27 draws them itself instead of letting each one place its own icon, so \(Constants.displayName) has to ask macOS to move them rather than moving them directly. Some refuse to move, some return to Visible on their own, and Clock and Control Center can only be hidden together with Siri.",
                systemImage: "flask.fill",
                tint: .blue
            )
        }
    }
}

/// Keep missing-item controls on the arrangement pane so users can find them, with details behind info buttons.
private struct LayoutUnshowableItemControls: View {
    @Bindable var general: GeneralSettings
    @Bindable var advanced: AdvancedSettings

    var body: some View {
        ThawSection {
            Text("Items macOS won’t show")
        } content: {
            // Thaw Bar Only is unplugged for now; restore this with the gate in MenuBarItemManager+ThawBarOnly.swift.
            // Toggle("Thaw Bar Only", isOn: $general.enableThawBarOnly)
            //     .annotation(
            //         "Keeps an item macOS won’t draw reachable in the \(Constants.displayName) Bar.",
            //         more: "Use it for an item that’s missing from the menu bar and can’t be placed there. Move it here from its menu in the layout editor. It counts as Hidden and opens from the \(Constants.displayName) Bar.\n\nTurn this off and those items become ordinary hidden items. Your list comes back when you turn it on again."
            //     )

            Toggle(isOn: $advanced.enableModuleStandIns) {
                HStack(spacing: ThawSpacing.compact) {
                    Text("Replace Control Center items")
                    ThawBadge.alpha
                }
            }
            .annotation(
                "\(Constants.displayName) icons replace Focus, AirDrop and others macOS hides.",
                more: "macOS hides Focus, AirDrop, Now Playing and Fast User Switching whenever any other item is hidden, even in Visible. \(Constants.displayName) puts its own icon in each one’s place, with the main actions in its menu. You can move or hide it like any item.\n\nTurn this off to bring the originals back."
            )
        }
    }
}

/// Share layout recovery with SimpleModeSettingsPane so correcting mistakes does not require advanced tuning.
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
                alwaysHiddenEnabled: alwaysHiddenEnabled,
                presentation: .card
            )
        }
    }
}

/// Reset appears in a titled section here and a quiet footnote under Simple Mode's folded bar.
struct LayoutResetFlow: View {
    enum Presentation {
        /// Explanatory sentence beside a glass button, inside a card.
        case card
        /// A trailing text button alone; the confirm row explains itself.
        case footnote
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let itemManager: MenuBarItemManager
    let controlItemsDisabled: Bool
    let alwaysHiddenEnabled: Bool
    var presentation: Presentation = .card

    @State private var isResetting = false
    @State private var isConfirming = false
    @State private var status: ResetStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if presentation == .card {
                    Text("Moves every movable item except the \(Constants.displayName) icon to the selected section, just like a fresh install.")
                        .font(ThawType.footnote)
                        .foregroundStyle(ThawInk.supporting)
                }
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
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var trigger: some View {
        switch presentation {
        case .card:
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
        case .footnote:
            Button {
                isConfirming = true
            } label: {
                if isResetting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Reset Layout…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(ThawInk.supporting)
                }
            }
            .buttonStyle(.plain)
        }
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

/// Not private: Simple Mode shows the same gate.
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
