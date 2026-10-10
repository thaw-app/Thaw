//
//  ControlItemPanelView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel
import SwiftUI
import ThawUI

// MARK: - ControlItemPanelView

/// The panel's contents: the status menu's live commands as controls.
/// Only commands with a state worth seeing at rest are here; the one-shot
/// entries that open something else stay in the menu.
struct ControlItemPanelView: View {
    private static let diagLog = DiagLog(category: "ControlItemPanel")

    let appState: AppState

    /// Called when a command has taken the panel's place, opening Settings,
    /// raising the search panel, so the panel does not linger over it.
    let dismiss: () -> Void

    /// Bumped whenever a section is revealed or hidden. Kept for the reason
    /// SwapBarView documents: the section objects compute isHidden from
    /// the section controller and are not observed.
    @State private var sectionRevision = 0

    /// Stored, never computed in body. A fresh publisher per body evaluation
    /// would re-subscribe, re-emit, bump the revision and loop forever.
    let sectionStateChanges: AnyPublisher<Void, Never>

    init(appState: AppState, dismiss: @escaping () -> Void) {
        self.appState = appState
        self.dismiss = dismiss
        let manager = appState.menuBarManager
        var publishers: [AnyPublisher<Void, Never>] = [
            manager.revealedSectionChanges.map { _ in () }.eraseToAnyPublisher(),
        ]
        for name in [MenuBarSection.Name.hidden, .alwaysHidden] {
            if let controlItem = manager.section(withName: name)?.controlItem {
                publishers.append(controlItem.$state.map { _ in () }.eraseToAnyPublisher())
            }
        }
        self.sectionStateChanges = Publishers.MergeMany(publishers)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private var profileManager: ProfileManager {
        appState.profileManager
    }

    private var activeProfileName: String {
        guard let id = profileManager.activeProfileID,
              let profile = profileManager.profiles.first(where: { $0.id == id })
        else {
            return String(localized: "No profile")
        }
        return profile.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            group("Show")
            sectionToggle(
                .hidden,
                symbol: "eye",
                title: "Hidden items",
                help: "Show or hide the items in the Hidden section"
            )
            sectionToggle(
                .alwaysHidden,
                symbol: "eye.slash",
                title: "Always Hidden items",
                help: "Show or hide the items in the Always Hidden section"
            )
            zenToggle

            Divider().padding(.vertical, ThawSpacing.hairline)

            group("Bar")
            profileRow
            swapBarToggle

            Divider().padding(.vertical, ThawSpacing.hairline)

            searchRow
            settingsRow
            quitRow
        }
        .padding(ThawSpacing.inset)
        .frame(width: 260, alignment: .leading)
        // The popover draws its own material, so the view does not layer the
        // panel glass on top of it.
        .fixedSize()
        .onReceive(sectionStateChanges) { _ in
            sectionRevision &+= 1
        }
    }

    private func group(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(ThawType.caption.weight(.semibold))
            .foregroundStyle(ThawInk.supporting)
            .padding(.leading, ThawSpacing.hairline)
    }

    // MARK: Sections

    private func sectionToggle(
        _ name: MenuBarSection.Name,
        symbol: String,
        title: LocalizedStringKey,
        help: LocalizedStringKey
    ) -> some View {
        let section = appState.menuBarManager.section(withName: name)
        let isShown = section.map { !$0.isHidden } ?? false
        return PanelToggleRow(symbol: symbol, title: title, help: help, isOn: isShown) {
            section?.toggle()
        }
        .disabled(section?.isEnabled != true)
    }

    private var zenToggle: some View {
        PanelToggleRow(
            symbol: "moon",
            title: "Zen Mode",
            help: "Hide the Hidden and Always Hidden items and keep hovering from revealing them. Turning it off brings back what was showing.",
            isOn: appState.menuBarManager.isZenModeActive
        ) {
            if !appState.menuBarManager.toggleZenMode() {
                Self.diagLog.debug("zen toggle refused")
            }
        }
    }

    // MARK: Bar

    private var profileRow: some View {
        Menu {
            ForEach(profileManager.profiles) { profile in
                Button {
                    apply(profile)
                } label: {
                    if profile.id == profileManager.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        } label: {
            HStack(spacing: ThawSpacing.row) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(ThawType.symbol)
                    .frame(width: 20)
                Text("Profile")
                    .font(ThawType.body)
                Spacer(minLength: ThawSpacing.row)
                Text(activeProfileName)
                    .font(ThawType.label)
                    .foregroundStyle(ThawInk.supporting)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(ThawType.micro.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, ThawSpacing.base)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .thawRowHover()
        .disabled(profileManager.profiles.isEmpty)
    }

    private var swapBarToggle: some View {
        @Bindable var advanced = appState.settings.advanced
        return PanelToggleRow(
            symbol: "arrow.left.arrow.right",
            title: "Swap Bar",
            help: "Show a floating bar at the bottom of the screen with buttons to swap the shown and hidden items, show sections, switch profiles and turn on Zen Mode",
            isOn: advanced.enableSwapBar
        ) {
            advanced.enableSwapBar.toggle()
        }
    }

    // MARK: Commands

    private var searchRow: some View {
        PanelCommandRow(symbol: "magnifyingglass", title: "Search items…") {
            dismiss()
            appState.menuBarManager.searchPanel.show()
        }
    }

    private var settingsRow: some View {
        PanelCommandRow(symbol: "gearshape", title: "Settings…") {
            dismiss()
            appState.activate(withPolicy: .regular)
            appState.openWindow(.settings)
        }
    }

    private var quitRow: some View {
        PanelCommandRow(symbol: "power", title: "Quit \(Constants.displayName)") {
            dismiss()
            ApplicationTermination.request()
        }
    }

    /// Switches profiles, answering a failed load through the HUD: the panel
    /// has no room for an error row and no window to put one in.
    private func apply(_ metadata: ProfileMetadata) {
        guard metadata.id != profileManager.activeProfileID else {
            return
        }
        let profile: Profile
        do {
            profile = try profileManager.loadProfile(id: metadata.id)
        } catch {
            Self.diagLog.error("profile \(metadata.id) failed to load: \(error)")
            ThawHUD.show(symbol: "exclamationmark.triangle", text: "Profile not applied")
            return
        }
        let previousID = profileManager.activeProfileID
        profileManager.activeProfileID = metadata.id
        profileManager.applyProfile(profile, to: appState, previousProfileID: previousID)
    }
}

// MARK: - Rows

/// A full-width row that reads as a switch: symbol, title, trailing state mark.
/// The whole width is the target, not just the control at the far end.
private struct PanelToggleRow: View {
    @Environment(\.isEnabled) private var isEnabled

    let symbol: String
    let title: LocalizedStringKey
    let help: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThawSpacing.row) {
                Image(systemName: symbol)
                    .font(ThawType.symbol)
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 20)
                Text(title)
                    .font(ThawType.body)
                Spacer(minLength: ThawSpacing.row)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(ThawType.symbol)
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, ThawSpacing.base)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        // Under Differentiate Without Color the accent alone is not a mark.
        .thawSelectionCue(
            isSelected: isOn,
            in: RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
        )
        .thawRowHover()
        .help(help)
        .opacity(isEnabled ? 1 : 0.4)
        // A button that acts as a switch: the toggle trait makes VoiceOver say
        // "switch" and read the state itself. It stays a button because a tap
        // runs an action (reveal, zen, swap) rather than writing a Bool.
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}

/// A row that does something once and has no state to show.
private struct PanelCommandRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ThawSpacing.row) {
                Image(systemName: symbol)
                    .font(ThawType.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(ThawType.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ThawSpacing.base)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .thawRowHover()
        .accessibilityLabel(title)
    }
}
