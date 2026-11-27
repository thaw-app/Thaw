//
//  ModulesSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// The optional parts of Thaw, as a list like the other pages or as cards.
/// Profiles is built in; the others are their own apps, and one that's off doesn't run.
struct ModulesSettingsPane: View {
    enum Layout: String {
        case list
        case grid
    }

    @Bindable var moduleHost: ModuleHost
    @Bindable var profiles: ProfilesFeature
    @SceneStorage("ModulesLayout") private var layout: Layout = .list

    init(moduleHost: ModuleHost, profiles: ProfilesFeature, layout: Layout = .list) {
        self.moduleHost = moduleHost
        self.profiles = profiles
        _layout = SceneStorage(wrappedValue: layout, "ModulesLayout")
    }

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: ThawSpacing.gutter, alignment: .top)]

    /// The search entry for a card's row.
    private static func searchAnchor(for card: ModuleCard) -> String {
        switch card.id {
        case "profiles": "modules.profiles"
        case "triggers": "modules.triggers"
        case "widgets": "modules.widgets"
        default: "modules.scripts"
        }
    }

    var body: some View {
        content
            .onAppear { moduleHost.refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("View", selection: $layout) {
                        Label("List", systemImage: "list.bullet").tag(Layout.list)
                        Label("Icons", systemImage: "square.grid.2x2").tag(Layout.grid)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .help("Show modules as a list or as icons")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .list:
            ThawForm {
                ThawSection {
                    ForEach(cards) { card in
                        ModuleRowView(card: card, moduleHost: moduleHost, profiles: profiles)
                            .settingsSearchAnchor(Self.searchAnchor(for: card))
                    }
                }
            }
        case .grid:
            ScrollView {
                LazyVGrid(columns: columns, spacing: ThawSpacing.gutter) {
                    ForEach(cards) { card in
                        ModuleCardView(card: card, moduleHost: moduleHost, profiles: profiles)
                            .settingsSearchAnchor(Self.searchAnchor(for: card))
                    }
                }
                .padding(ThawSpacing.section)
            }
        }
    }

    // MARK: Cards

    /// Profiles first, then the installed modules by name.
    private var cards: [ModuleCard] {
        let modules = moduleHost.modules
            .compactMap { _, module -> ModuleCard? in
                guard let manifest = module.manifest else { return nil }
                return ModuleCard(
                    kind: .module(manifest.identifier),
                    name: manifest.name,
                    summary: Self.summary(for: manifest.identifier, state: module.state),
                    pane: Self.pane(for: manifest.identifier)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let profilesCard = ModuleCard(
            kind: .profiles,
            name: String(localized: "Profiles"),
            summary: String(localized: "Switches saved layouts by display, Space, Focus or shortcut."),
            pane: .profiles
        )
        return [profilesCard] + modules
    }

    static func pane(for identifier: String) -> SettingsNavigationIdentifier {
        switch ModuleIdentifier(rawValue: identifier) {
        case .scripts: .scripts
        case .triggers: .triggers
        case .widgets, nil: .widgets
        }
    }

    /// What a module does, or why it isn't running when it should be.
    static func summary(for identifier: String, state: ModuleHost.State) -> String {
        switch state {
        case .refused(.untrusted):
            return String(localized: "Not signed by \(Constants.displayName)'s developers, so it won't run.")
        case .refused(.needsNewerThaw):
            return String(localized: "Needs a newer version of \(Constants.displayName).")
        case .gaveUp:
            return String(localized: "Stopped after it kept quitting. Switch it off and on to try again.")
        case .launchFailed:
            return String(localized: "Couldn't start. Switch it off and on to try again.")
        case .idle, .running, .restarting, .stopped, .refused(.launch), .refused(.notAModule):
            switch ModuleIdentifier(rawValue: identifier) {
            case .scripts: return String(localized: "Runs your scripts when a profile switches.")
            case .triggers: return String(localized: "Shows chosen menu bar items while an app runs or when their icon changes.")
            case .widgets: return String(localized: "Shows battery, Wi-Fi and other readings in one menu bar icon.")
            case nil: return ""
            }
        }
    }
}

/// One part of Thaw that can be switched on or off.
struct ModuleCard: Identifiable, Equatable {
    enum Kind: Equatable {
        case profiles
        /// A module app, by its identifier.
        case module(String)
    }

    let kind: Kind
    let name: String
    let summary: String
    /// The page whose icon the card shows.
    let pane: SettingsNavigationIdentifier

    var id: String {
        switch kind {
        case .profiles: "profiles"
        case let .module(identifier): identifier
        }
    }
}

/// A part's name with what it does under it. Cards keep three lines for the
/// description so a row of them lines up.
private struct ModuleLabel: View {
    @Environment(\.settingsDescriptionsVisible) private var descriptionsVisible
    let card: ModuleCard
    var isCard = false

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
            Text(verbatim: card.name)
                .font(ThawType.label)
                .lineLimit(1)
            if isCard {
                Text(verbatim: card.summary)
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .lineLimit(3, reservesSpace: true)
            } else if descriptionsVisible {
                Text(verbatim: card.summary)
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The part's switch, with Open… for a module that's on.
private struct ModuleCardControls: View {
    let card: ModuleCard
    @Bindable var moduleHost: ModuleHost
    @Bindable var profiles: ProfilesFeature

    var body: some View {
        switch card.kind {
        case .profiles:
            Toggle(isOn: $profiles.isOn) {
                Text(verbatim: card.name)
            }
            .labelsHidden()
            .toggleStyle(.switch)
        case let .module(identifier):
            ModuleControls(moduleHost: moduleHost, identifier: identifier, name: card.name)
        }
    }
}

private struct ModuleRowView: View {
    let card: ModuleCard
    @Bindable var moduleHost: ModuleHost
    @Bindable var profiles: ProfilesFeature

    var body: some View {
        LabeledContent {
            ModuleCardControls(card: card, moduleHost: moduleHost, profiles: profiles)
        } label: {
            HStack(spacing: ThawSpacing.row) {
                SettingsPaneIconTile(identifier: card.pane, side: 32)
                ModuleLabel(card: card)
            }
            .padding(.vertical, ThawSpacing.tight)
        }
    }
}

private struct ModuleCardView: View {
    let card: ModuleCard
    @Bindable var moduleHost: ModuleHost
    @Bindable var profiles: ProfilesFeature

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
            SettingsPaneIconTile(identifier: card.pane, side: 40)
            ModuleLabel(card: card, isCard: true)
            HStack {
                Spacer(minLength: 0)
                ModuleCardControls(card: card, moduleHost: moduleHost, profiles: profiles)
            }
            .frame(minHeight: 24)
        }
        .padding(ThawSpacing.gutter)
        .background(.quinary, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: card.name))
    }
}
