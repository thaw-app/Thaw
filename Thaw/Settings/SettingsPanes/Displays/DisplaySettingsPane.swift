//
//  DisplaySettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Keep shared state and alerts here: SwiftUI cannot present alert actions moved into nested View types.
/// Internal @State lets sibling-file extensions share it; callers use its defaults.
struct DisplaySettingsPane: View {
    @Environment(AppState.self) var appState
    @Bindable var displaySettings: DisplaySettingsManager

    /// Slider edits remain drafts until Apply, without saving configuration or relaunching apps.
    @State var draftSpacing: [String: CGFloat] = [:]
    /// Non-nil while a spacing apply awaits confirmation.
    @State var pendingSpacingApply: PendingSpacingApply?
    /// Non-nil while a global broadcast awaits confirmation.
    @State var pendingGlobalApply: PendingGlobalApply?
    @State var errorMessage: String?
    @State var selectedDisplayID: String?

    @State private var tab = DisplaysTab.spacing

    var body: some View {
        ThawForm {
            // didSet cannot throw; surface write failures so unsaved values do not silently vanish on relaunch.
            if let failure = displaySettings.lastPersistenceFailure {
                SettingsWarningPill(
                    title: "Display settings weren’t saved",
                    message: "\(failure) The settings below are in effect now, but they will be back to their last saved values after a restart.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }

            // The arrangement selects the display edited below.
            if selectedDisplay != nil {
                ThawSection {
                    displaySelector
                }
            }

            SettingsPaneTabs(
                selection: $tab,
                tabs: DisplaysTab.allCases,
                tabForSection: DisplaysTab.init(section:)
            )

            switch tab {
            case .spacing:
                // The relaunch confirmation sits with spacing, since it decides when spacing edits apply.
                ThawSection("Menu bar item spacing") {
                    globalSection()
                    confirmSpacingRelaunchControls
                }
                if selectedDisplay != nil {
                    ThawSection {
                        Text("Per display")
                    } content: {
                        perDisplayControls
                    }
                }
            case .spaces:
                // Spaces belong to displays in macOS, so their controls follow the display's.
                SpacesControlsContent(activeSpaceID: UInt64(bitPattern: Int64(appState.activeSpace.spaceID)))
            case .wideDisplays:
                WideDisplayRuleSection(rule: displaySettings.wideDisplayRule)
            }
        }
        .alert(
            String(localized: "Apply spacing change?"),
            item: $pendingSpacingApply,
            actions: { pending in spacingConfirmationButtons(for: pending) },
            message: { pending in Text(spacingConfirmationMessage(for: pending)) }
        )
        .alert(
            String(localized: "Apply template to all displays?"),
            item: $pendingGlobalApply,
            actions: { pending in globalConfirmationButtons(for: pending) },
            message: { pending in Text(globalConfirmationMessage(for: pending)) }
        )
        .errorAlert("Couldn’t save display settings", message: $errorMessage)
    }

    @ViewBuilder
    private var confirmSpacingRelaunchControls: some View {
        ThawPicker("When spacing changes", selection: spacingApplyChoice) {
            Text("Ask before restarting menu bar apps").tag(SpacingApplyChoice.askFirst)
            Text("Restart menu bar apps right away").tag(SpacingApplyChoice.relaunchNow)
            Text("Wait until the apps restart").tag(SpacingApplyChoice.waitForRestart)
        }
        .annotation(
            "macOS only reads the spacing when an app with a menu bar item starts.",
            more: "Restarting apps applies the change now; waiting leaves every app running and the new spacing appears the next time each app starts (after a restart, or when you reopen it)."
        )

        // Without a question to ask, the change needs to know which profiles it is saved to.
        if spacingApplyChoice.wrappedValue == .relaunchNow {
            Toggle("Save spacing to every profile", isOn: Binding(
                get: { displaySettings.unconfirmedSpacingProfileScope == .allProfiles },
                set: { displaySettings.unconfirmedSpacingProfileScope = $0 ? .allProfiles : .activeProfile }
            ))
            .annotation("When a profile is active and this is off, a spacing change saves to that profile only.")
        }
    }

    private var spacingApplyChoice: Binding<SpacingApplyChoice> {
        Binding(
            get: { SpacingApplyChoice(mode: displaySettings.spacingApplyMode, confirms: displaySettings.confirmSpacingRelaunch) },
            set: { choice in
                displaySettings.spacingApplyMode = choice.mode
                if let confirms = choice.confirms {
                    displaySettings.confirmSpacingRelaunch = confirms
                }
            }
        )
    }
}

/// The rule that shows every item while the menu bar is on a wide display.
private struct WideDisplayRuleSection: View {
    @Bindable var rule: WideDisplayRule

    var body: some View {
        ThawSection("Wide displays") {
            Toggle("Show every item on wide displays", isOn: $rule.isEnabled)
                .annotation("While the menu bar is on a display at least this wide, hidden items stay in the menu bar, as if “Always show hidden items” were on for that display.")

            if rule.isEnabled {
                LabeledContent {
                    ThawSlider(value: $rule.minimumWidth, in: WideDisplayRule.widthRange, step: 160) {
                        Text(verbatim: "\(Int(rule.minimumWidth)) pt")
                            .monospacedDigit()
                    }
                } label: {
                    Text("At least")
                }
            }
        }
    }
}

nonisolated enum DisplaysTab: CaseIterable, ThawTab {
    case spacing
    case spaces
    case wideDisplays

    /// The tab holding a search result's section.
    init?(section: String) {
        switch section {
        case "Menu bar item spacing": self = .spacing
        case "This Space", "All Spaces": self = .spaces
        case "Wide displays": self = .wideDisplays
        default: return nil
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .spacing: "Spacing"
        case .spaces: "Spaces"
        case .wideDisplays: "Wide Displays"
        }
    }

    var systemImage: String {
        switch self {
        case .spacing: "arrow.left.and.right.text.vertical"
        case .spaces: "rectangle.split.3x1"
        case .wideDisplays: "display"
        }
    }
}
