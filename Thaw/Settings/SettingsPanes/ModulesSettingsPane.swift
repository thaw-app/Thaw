//
//  ModulesSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawModuleKit
import ThawUI

/// The optional parts of Thaw as searchable cards, like Floe's extension store.
/// Profiles is built in; the others are their own apps, and one that's off doesn't run.
struct ModulesSettingsPane: View {
    @Bindable var moduleHost: ModuleHost
    @Bindable var profiles: ProfilesFeature
    @State private var query = ""

    /// Cards about as wide as Floe's store cards, as many to a row as fit.
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: ThawSpacing.gutter, alignment: .top)]

    var body: some View {
        let shown = Self.matching(cards, query: query)
        VStack(spacing: 0) {
            SettingsFilterField(prompt: "Search modules", clearLabel: "Clear search", text: $query)
                .padding(ThawSpacing.inset)
            ScrollView {
                LazyVGrid(columns: columns, spacing: ThawSpacing.gutter) {
                    ForEach(shown) { card in
                        ModuleCardView(card: card, moduleHost: moduleHost, profiles: profiles)
                    }
                }
                .padding(.horizontal, ThawSpacing.inset)
                .padding(.bottom, ThawSpacing.inset)
            }
            .overlay {
                if shown.isEmpty, !query.isEmpty {
                    NoMatchesState(
                        query: query,
                        title: { "No modules match “\($0)”" },
                        caption: "Try a shorter or broader term."
                    )
                }
            }
        }
        .onAppear { moduleHost.refresh() }
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

    /// The cards whose name or description contains every word of the query.
    static func matching(_ cards: [ModuleCard], query: String) -> [ModuleCard] {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return cards }
        return cards.filter { card in
            words.allSatisfy { word in
                card.name.localizedStandardContains(word) || card.summary.localizedStandardContains(word)
            }
        }
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

/// One card: the part's icon, name and description, then its switch.
private struct ModuleCardView: View {
    let card: ModuleCard
    @Bindable var moduleHost: ModuleHost
    @Bindable var profiles: ProfilesFeature

    var body: some View {
        VStack(spacing: ThawSpacing.base) {
            SettingsPaneIconTile(identifier: card.pane, side: 40)
            VStack(spacing: ThawSpacing.hairline) {
                Text(verbatim: card.name)
                    .lineLimit(1)
                Text(verbatim: card.summary)
                    .font(ThawType.detail)
                    .foregroundStyle(ThawInk.supporting)
                    .lineLimit(3, reservesSpace: true)
            }
            .multilineTextAlignment(.center)
            control
        }
        .padding(ThawSpacing.inset)
        .frame(maxWidth: .infinity)
        .background(.quinary, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: card.name))
    }

    @ViewBuilder
    private var control: some View {
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
