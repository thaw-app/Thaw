//
//  WhatsNewSwitches.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Which switches What's New offers: the running release's own, then older ones still off,
/// so someone who never opens Experiments still meets them.
nonisolated enum WhatsNewSwitchOffer {
    struct Candidate: Equatable {
        let id: String
        let since: String
        let isOn: Bool
    }

    static func offered(_ candidates: [Candidate], release: String) -> [String] {
        let new = candidates.filter { $0.since == release }
        let olderStillOff = candidates.filter { $0.since != release && !$0.isOn }
        return (new + olderStillOff).map(\.id)
    }
}

/// A switch What's New can offer, bound to the same setting as in Settings.
@MainActor
struct WhatsNewSwitch: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    /// The release it first shipped in, as the changelog spells it.
    let since: String
    let keyPath: ReferenceWritableKeyPath<AdvancedSettings, Bool>

    /// The off-by-default features What's New can offer. A release that adds
    /// one lists it here with its version.
    static let all: [WhatsNewSwitch] = [
        WhatsNewSwitch(
            id: "controlItemPanel",
            title: "Panel instead of the status menu",
            detail: "Right-click \(Constants.displayName)’s icon for a panel of controls.",
            since: "3.0.0-alpha.6",
            keyPath: \.enableControlItemPanel
        ),
        WhatsNewSwitch(
            id: "itemDescenders",
            title: "Show item details on hover",
            detail: "A small readout under an item while the pointer rests on it.",
            since: "3.0.0-alpha.1",
            keyPath: \.enableMenuBarItemDescenders
        ),
        WhatsNewSwitch(
            id: "recordingWatch",
            title: "Camera and microphone watch",
            detail: "A banner names the app that turned on the microphone or camera.",
            since: "3.0.0-alpha.1",
            keyPath: \.enableRecordingWatch
        ),
        WhatsNewSwitch(
            id: "desktopMenuHiding",
            title: "Hide Finder menus on the desktop",
            detail: "Covers Finder’s menus after you click the desktop.",
            since: "3.0.0-alpha.1",
            keyPath: \.enableDesktopMenuHiding
        ),
    ]

    static func offered(release: String, settings: AdvancedSettings) -> [WhatsNewSwitch] {
        let candidates = all.map {
            WhatsNewSwitchOffer.Candidate(id: $0.id, since: $0.since, isOn: settings[keyPath: $0.keyPath])
        }
        let ids = WhatsNewSwitchOffer.offered(candidates, release: release)
        return ids.compactMap { id in all.first { $0.id == id } }
    }
}

/// The switches at the top of the running release's notes. The list is
/// fixed when the view appears, so a switch turned on here stays in place.
struct WhatsNewSwitchesView: View {
    @Bindable var settings: AdvancedSettings
    @State private var switches: [WhatsNewSwitch]

    init(settings: AdvancedSettings) {
        self.settings = settings
        _switches = State(initialValue: WhatsNewSwitch.offered(release: Constants.versionString, settings: settings))
    }

    var body: some View {
        if !switches.isEmpty {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try these")
                .font(ReadingPageType.heading)
                .accessibilityAddTraits(.isHeader)
            Text("Experiments you haven’t turned on yet. You can turn them off later in Settings › Experiments.")
                .font(ReadingPageType.body)
                .foregroundStyle(.secondary)
            ForEach(switches) { item in
                Toggle(isOn: $settings[dynamicMember: item.keyPath]) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }
}
