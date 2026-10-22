//
//  ControlCenterReplacementsSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
import SwiftUI
import ThawUI

/// The replacement settings as Layout's one switch and its list.
/// On when any is on, so one turned on before the switches merged still reads as on.
struct ControlCenterReplacements: Equatable {
    var modules: Bool
    var timeMachine: Bool
    var textInput: Bool
    /// The Control Center modules left as Apple's own while modules is on.
    var skipped: Set<SystemExtraStandIn> = []

    /// The four Control Center modules one switch used to cover.
    static let modules: [SystemExtraStandIn] = [.focus, .airDrop, .nowPlaying, .userSwitcher]

    /// Every item the list offers, in the order it shows them.
    static let listed: [SystemExtraStandIn] = modules + [.timeMachine, .textInput]

    var isOn: Bool {
        get { Self.listed.contains { isReplaced($0) } }
        set {
            modules = newValue
            timeMachine = newValue
            textInput = newValue
            skipped = []
        }
    }

    func isReplaced(_ item: SystemExtraStandIn) -> Bool {
        switch item {
        case .timeMachine: timeMachine
        case .textInput: textInput
        case .timer: false
        case .focus, .airDrop, .nowPlaying, .userSwitcher: modules && !skipped.contains(item)
        }
    }

    /// Replaces one item or gives it back. Leaving all four modules out
    /// turns the modules setting off, so turning the switch on again starts
    /// from all of them.
    mutating func setReplaced(_ item: SystemExtraStandIn, _ replaced: Bool) {
        switch item {
        case .timeMachine:
            timeMachine = replaced
        case .textInput:
            textInput = replaced
        case .timer:
            break
        case .focus, .airDrop, .nowPlaying, .userSwitcher:
            if replaced {
                if !modules {
                    modules = true
                    skipped = Set(Self.modules)
                }
                skipped.remove(item)
            } else {
                skipped.insert(item)
            }
            if skipped.isSuperset(of: Self.modules) {
                modules = false
                skipped = []
            }
        }
    }
}

extension AdvancedSettings {
    var controlCenterReplacements: ControlCenterReplacements {
        get {
            ControlCenterReplacements(
                modules: enableModuleStandIns,
                timeMachine: enableTimeMachineTakeover,
                textInput: enableTextInputTakeover,
                skipped: Set(skippedModuleStandIns.compactMap(SystemExtraStandIn.init(rawValue:)))
            )
        }
        set {
            enableModuleStandIns = newValue.modules
            enableTimeMachineTakeover = newValue.timeMachine
            enableTextInputTakeover = newValue.textInput
            skippedModuleStandIns = Set(newValue.skipped.map(\.rawValue))
        }
    }
}

/// One switch for every Apple item Thaw can stand in for: the four Control Center modules
/// macOS hides together, plus Time Machine and the Input menu, which it will not hide.
/// While it is on, a list under it picks which ones are replaced.
struct ControlCenterReplacementsSection: View {
    @Bindable var settings: AdvancedSettings
    @Environment(AppState.self) private var appState

    /// The extras that report whether their replacement is running.
    private static let reportingItems: [SystemExtraItem] = [.timeMachine, .textInput]

    var body: some View {
        ThawSection {
            Text("Apple’s items")
        } content: {
            Toggle(isOn: $settings.controlCenterReplacements.isOn) {
                HStack(spacing: ThawSpacing.compact) {
                    Text("Replace Control Center items")
                    ThawBadge.alpha
                }
            }
            .annotation {
                VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                    Text(
                        """
                        macOS hides Focus, AirDrop, Now Playing and Fast User Switching whenever any \
                        other item is hidden, and never hides Time Machine or the Input menu. This puts a \
                        \(Constants.displayName) icon in each one’s place that does the same things, and \
                        you can move or hide it like any other item. Choose which ones below; turn this off \
                        to bring the originals back.
                        """
                    )
                    // Only a failure shows, so a replacement that cannot run never reads as working.
                    ForEach(Self.reportingItems) { item in
                        status(for: item)
                    }
                }
            }
            if settings.controlCenterReplacements.isOn {
                ForEach(ControlCenterReplacements.listed, id: \.self) { item in
                    Toggle(Self.name(of: item), isOn: Binding(
                        get: { settings.controlCenterReplacements.isReplaced(item) },
                        set: { settings.controlCenterReplacements.setReplaced(item, $0) }
                    ))
                    .toggleStyle(.thawCheckbox)
                }
            }
        }
    }

    private static func name(of item: SystemExtraStandIn) -> LocalizedStringKey {
        switch item {
        case .focus: "Focus"
        case .airDrop: "AirDrop"
        case .nowPlaying: "Now Playing"
        case .userSwitcher: "Fast User Switching"
        case .timeMachine: "Time Machine"
        case .textInput: "Input menu"
        case .timer: "Timer"
        }
    }

    @ViewBuilder
    private func status(for item: SystemExtraItem) -> some View {
        switch appState.menuBarManager.systemExtraTakeover.status(for: item).phase {
        case .off, .ready, .active:
            EmptyView()
        case let .unavailable(reason), let .failed(reason):
            Label {
                Text(verbatim: reason)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .foregroundStyle(Color.warning)
        }
    }
}
