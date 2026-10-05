//
//  DisplayPerDisplaySection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Selection and spacing controls for currently connected displays.
extension DisplaySettingsPane {
    /// Fall back to the first connected display for stale or unset selections.
    var selectedDisplay: DisplaySettingsManager.DisplayInfo? {
        let displays = displaySettings.connectedDisplays()
        return displays.first(where: { $0.id == selectedDisplayID }) ?? displays.first
    }

    /// Thumbnail selection determines the target of the per-display controls.
    @ViewBuilder
    var displaySelector: some View {
        if let selected = selectedDisplay {
            DisplaySpatialSelector(
                displays: displaySettings.connectedDisplays(),
                selectedDisplayID: Binding(
                    get: { selected.id },
                    set: { selectedDisplayID = $0 }
                )
            )
        }
    }

    /// Share one controls block across display selections instead of repeating it per display.
    @ViewBuilder
    var perDisplayControls: some View {
        if let selected = selectedDisplay {
            displayHeader(for: selected)
                .frame(maxWidth: .infinity, alignment: .leading)

            displayRow(for: selected)
        }
    }

    // MARK: - Header

    /// Always name the thumbnail selection and attach its Customized badge to that display.
    private func displayHeader(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        HStack(spacing: 6) {
            Text(display.name)

            if display.hasNotch {
                ThawBadge("Notch")
            }
            if !display.isConnected {
                ThawBadge("Disconnected")
            }
            if differsFromTemplate(display) {
                ThawBadge("Customized", tone: .tinted(.accentColor))
                    .help(Text("This display’s settings differ from the global template"))
            }

            Spacer(minLength: 8)

            if differsFromTemplate(display) {
                Button("Use Template") {
                    applyTemplate(to: display)
                }
                .buttonStyle(.settingsGlass)
                .controlSize(.small)
                .help(Text("Copy the global template’s settings onto this display"))
            }
        }
    }

    // MARK: - Template relationship

    /// Compare the whole configuration, including spacing, to match template broadcast eligibility.
    private func differsFromTemplate(_ display: DisplaySettingsManager.DisplayInfo) -> Bool {
        displaySettings.configuration(forUUID: display.id) != displaySettings.globalConfiguration
    }

    /// Spacing uses requestSpacingApply's confirmation because it can relaunch apps on the active display.
    /// Other template controls are individually reversible and need no prompt.
    private func applyTemplate(to display: DisplaySettingsManager.DisplayInfo) {
        let template = displaySettings.globalConfiguration
        let spacingDiffers = displaySettings.configuration(forUUID: display.id).itemSpacingOffset
            != template.itemSpacingOffset

        displaySettings.updateConfiguration(forDisplayUUID: display.id) { config in
            config
                .withUseThawBar(template.useThawBar)
                .withThawBarLocation(template.thawBarLocation)
                .withThawBarLayout(template.thawBarLayout)
                .withGridColumns(template.gridColumns)
                .withAlwaysShowHiddenItems(template.alwaysShowHiddenItems)
        }

        if spacingDiffers {
            requestSpacingApply(for: display, offset: Double(template.itemSpacingOffset))
        }
    }

    // MARK: - Controls

    private func displayRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        spacingRow(for: display)
    }

    // MARK: - Spacing

    @ViewBuilder
    private func spacingRow(for display: DisplaySettingsManager.DisplayInfo) -> some View {
        let savedOffset = displaySettings.configuration(forUUID: display.id).itemSpacingOffset
        let draft = draftSpacing[display.id] ?? CGFloat(savedOffset)
        let isPending = draft != CGFloat(savedOffset)

        let sliderBinding = Binding<CGFloat>(
            get: { draftSpacing[display.id] ?? CGFloat(savedOffset) },
            set: { draftSpacing[display.id] = $0 }
        )

        LabeledContent {
            ThawSlider(
                value: sliderBinding,
                in: -16 ... 16,
                step: 2
            ) {
                spacingValueLabel(draft)
            }
        } label: {
            LabeledContent {
                // Reset acts on the saved value, so it stays available without a pending draft.
                Button {
                    requestSpacingApply(for: display, offset: 0)
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.plain)
                .help(Text("Reset to the default spacing"))
                .accessibilityLabel(Text("Reset to the default spacing"))
                .disabled(savedOffset == 0 && draft == 0)
            } label: {
                Text("Menu bar item spacing")
            }
        }
        .annotation(spacingRowAnnotation)
        .onChange(of: savedOffset) { _, newValue in
            // External changes, including profiles and URLs, replace the draft with the saved value.
            draftSpacing[display.id] = CGFloat(newValue)
        }

        if isPending {
            spacingPendingStrip(for: display, draft: draft, savedOffset: savedOffset)
        } else if display.id == displaySettings.activeMenuBarDisplayUUID,
                  displaySettings.spacingApplyMode == .relaunchApps
        {
            LabeledContent {
                Button(displaySettings.isReapplyingSpacing ? "Reapplying…" : "Reapply Spacing") {
                    displaySettings.reapplySpacing(forDisplayUUID: display.id)
                }
                .buttonStyle(.settingsGlass)
                .disabled(displaySettings.isReapplyingSpacing)
            } label: {
                Text("Spacing hasn’t updated?")
            }
            .annotation("Relaunches menu bar apps to reload the saved spacing.")
        }
        if let failure = displaySettings.lastSpacingApplyFailure {
            SettingsWarningPill(
                message: "\(failure)",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    /// Write-only mode restarts nothing, so the copy must not promise a relaunch.
    private var spacingRowAnnotation: LocalizedStringKey {
        if displaySettings.spacingApplyMode == .writeOnly {
            "Takes effect when this display is the active menu bar display. Applying it writes the new value without restarting apps; each app picks it up the next time it starts, and each app can add its own padding, so gaps are not always identical."
        } else {
            "Takes effect when this display is the active menu bar display. Applying it restarts menu bar apps so they load the new value, and each app can add its own padding, so gaps are not always identical."
        }
    }

    private var spacingPendingNotice: LocalizedStringKey {
        if displaySettings.spacingApplyMode == .writeOnly {
            "Apps pick up the new spacing the next time they start"
        } else {
            "Applying relaunches apps with menu bar items"
        }
    }

    /// Use meaningful endpoint labels and one metric font to avoid size and width jitter while dragging.
    private func spacingValueLabel(_ draft: CGFloat) -> some View {
        Group {
            switch draft {
            case -16: Text("None")
            case 0: Text("Default")
            case 16: Text("Max")
            default: Text(verbatim: draft.formatted())
            }
        }
        .font(ThawType.metric)
    }

    /// Attach the relaunch warning to pending changes; requestSpacingApply still handles confirmation and profile scope.
    /// Use a flat accent wash inside the glass form row to avoid nested glass.
    private func spacingPendingStrip(
        for display: DisplaySettingsManager.DisplayInfo,
        draft: CGFloat,
        savedOffset: Double
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)

        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(spacingPendingNotice)
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Discard") {
                // Dragging changes only the draft, so restoring the saved value fully discards it.
                draftSpacing[display.id] = CGFloat(savedOffset)
            }
            .buttonStyle(.settingsGlass)
            .controlSize(.small)
            .help(Text("Discard the pending spacing change"))

            Button("Apply") {
                requestSpacingApply(for: display, offset: Double(draft))
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .help(Text("Apply the spacing for this display"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Match ThawBadge's flat tinted wash.
        .background(Color.accentColor.opacity(0.16), in: shape)
        .overlay(shape.strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
