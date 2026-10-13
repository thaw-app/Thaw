//
//  ControlCenterReplacementsSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
import SwiftUI
import ThawUI

/// The three replacement settings as Layout's one switch.
/// On when any is on, so one turned on before the switches merged still reads as on.
struct ControlCenterReplacements: Equatable {
    var modules: Bool
    var timeMachine: Bool
    var textInput: Bool

    var isOn: Bool {
        get { modules || timeMachine || textInput }
        set {
            modules = newValue
            timeMachine = newValue
            textInput = newValue
        }
    }
}

extension AdvancedSettings {
    var controlCenterReplacements: ControlCenterReplacements {
        get {
            ControlCenterReplacements(
                modules: enableModuleStandIns,
                timeMachine: enableTimeMachineTakeover,
                textInput: enableTextInputTakeover
            )
        }
        set {
            enableModuleStandIns = newValue.modules
            enableTimeMachineTakeover = newValue.timeMachine
            enableTextInputTakeover = newValue.textInput
        }
    }
}

/// One switch for every Apple item Thaw can stand in for: the four Control Center modules
/// macOS hides together, plus Time Machine and the Input menu, which it will not hide.
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
                        you can move or hide it like any other item. Turn this off to bring the originals back.
                        """
                    )
                    // Only a failure shows, so a replacement that cannot run never reads as working.
                    ForEach(Self.reportingItems) { item in
                        status(for: item)
                    }
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
