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
    /// Wi-Fi, Bluetooth and Sound, each turned on by its own box.
    var optIn: Set<SystemExtraStandIn> = []
    /// The Control Center modules left as Apple's own while modules is on.
    var skipped: Set<SystemExtraStandIn> = []

    /// The four Control Center modules one switch used to cover.
    static let moduleItems: [SystemExtraStandIn] = [.focus, .airDrop, .nowPlaying, .userSwitcher]

    /// Their menus differ from Apple's, so the switch never turns them on.
    static let optInItems: [SystemExtraStandIn] = [.wiFi, .bluetooth, .sound]

    /// Every item the list offers, in the order it shows them.
    static let listed: [SystemExtraStandIn] = moduleItems + [.timeMachine, .textInput] + optInItems

    var isOn: Bool {
        get { Self.listed.contains { isReplaced($0) } }
        set {
            modules = newValue
            timeMachine = newValue
            textInput = newValue
            if !newValue {
                optIn = []
            }
            skipped = []
        }
    }

    func isReplaced(_ item: SystemExtraStandIn) -> Bool {
        switch item {
        case .timeMachine: timeMachine
        case .textInput: textInput
        case .wiFi, .bluetooth, .sound: optIn.contains(item)
        case .timer, .space: false
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
        case .wiFi, .bluetooth, .sound:
            if replaced {
                optIn.insert(item)
            } else {
                optIn.remove(item)
            }
        case .timer, .space:
            break
        case .focus, .airDrop, .nowPlaying, .userSwitcher:
            if replaced {
                if !modules {
                    modules = true
                    skipped = Set(Self.moduleItems)
                }
                skipped.remove(item)
            } else {
                skipped.insert(item)
            }
            if skipped.isSuperset(of: Self.moduleItems) {
                modules = false
                skipped = []
            }
        }
    }
}

extension LayoutSettings {
    var controlCenterReplacements: ControlCenterReplacements {
        get {
            ControlCenterReplacements(
                modules: enableModuleStandIns,
                timeMachine: enableTimeMachineTakeover,
                textInput: enableTextInputTakeover,
                optIn: Set(optInStandIns.compactMap(SystemExtraStandIn.init(rawValue:))),
                skipped: Set(skippedModuleStandIns.compactMap(SystemExtraStandIn.init(rawValue:)))
            )
        }
        set {
            enableModuleStandIns = newValue.modules
            enableTimeMachineTakeover = newValue.timeMachine
            enableTextInputTakeover = newValue.textInput
            optInStandIns = Set(newValue.optIn.map(\.rawValue))
            skippedModuleStandIns = Set(newValue.skipped.map(\.rawValue))
        }
    }
}

/// One switch for every Apple item Thaw can stand in for: the four Control Center modules
/// macOS hides together, plus Time Machine and the Input menu, which it will not hide.
/// While it is on, a list under it picks which ones are replaced.
struct ControlCenterReplacementsSection: View {
    @Bindable var settings: LayoutSettings
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
                        .settingsSearchAnchor("layout.replaceControlCenterItems")
                    ThawBadge.beta
                }
            }
            .annotation {
                VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                    Text(
                        """
                        Puts a \(Constants.displayName) icon in place of each item you choose below, which \
                        you can move or hide like any other item. Wi-Fi, Bluetooth and Sound get menus of their own; \
                        Apple's are still in Control Center. Turn this off to bring the originals back.
                        """
                    )
                    // Only a failure shows, so a replacement that cannot run never reads as working.
                    ForEach(Self.reportingItems) { item in
                        status(for: item)
                    }
                }
            }
            FocusStandInNotice(settings: settings, focusShownInControlCenter: FocusStandInNotice.focusShownInControlCenter())
            if settings.controlCenterReplacements.isOn {
                ForEach(ControlCenterReplacements.listed, id: \.self) { item in
                    Toggle(item.replacementName, isOn: Binding(
                        get: { settings.controlCenterReplacements.isReplaced(item) },
                        set: { settings.controlCenterReplacements.setReplaced(item, $0) }
                    ))
                    .toggleStyle(.thawCheckbox)
                }
            }
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

private extension SystemExtraStandIn {
    /// The item's name in the replacement list.
    var replacementName: LocalizedStringKey {
        switch self {
        case .focus: "Focus"
        case .airDrop: "AirDrop"
        case .nowPlaying: "Now Playing"
        case .userSwitcher: "Fast User Switching"
        case .timeMachine: "Time Machine"
        case .textInput: "Input menu"
        case .timer: "Timer"
        case .space: "Space"
        case .wiFi: "Wi-Fi"
        case .bluetooth: "Bluetooth"
        case .sound: "Sound"
        }
    }
}
