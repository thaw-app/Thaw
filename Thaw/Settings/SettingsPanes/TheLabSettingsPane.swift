//
//  TheLabSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import PlatformRuntimeKit
import SwiftUI
import ThawUI

/// Home for unfinished ideas users can opt into early.
///
/// Turning a row off always restores normal behavior. Rows graduate to their
/// proper pane when they stabilize.
struct TheLabSettingsPane: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: AdvancedSettings

    /// Bumped on display-configuration changes so the announcement-screen
    /// picker re-reads the live display list. Read in the body through
    /// announcementScreenChoices.
    @State private var screenGeneration = 0

    var body: some View {
        ThawForm {
            // A short unbordered caution; specific risks sit beside each feature.
            ThawSection(isBordered: false) {
                Text("Early ideas. They can change, break, or go away between releases. Turning one off puts \(Constants.displayName) back to normal.")
                    .font(ThawType.footnote)
                    .foregroundStyle(ThawInk.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ThawSection("Menu bar items") {
                enableMenuBarItemDescenders
                enableModuleStandIns
                systemExtraTakeoverToggle(
                    "Replace Time Machine",
                    isOn: $settings.enableTimeMachineTakeover,
                    item: .timeMachine
                )
                systemExtraTakeoverToggle(
                    "Replace Input Menu",
                    isOn: $settings.enableTextInputTakeover,
                    item: .textInput
                )
                enableDesktopMenuHiding
            }
            ThawSection("\(Constants.displayName)'s menu and icon") {
                enableControlItemPanel
                enableCustomStatusIcon
            }
            // Feedback links go last; the list is the point.
            ThawSection {
                Text("Camera and microphone")
            } content: {
                enableRecordingWatch
            } footer: {
                HStack(spacing: ThawSpacing.inset) {
                    Text("Tell us how an experiment goes")
                        .font(ThawType.footnote)
                        .foregroundStyle(ThawInk.supporting)
                    // Real links, so VoiceOver says "link", styled alike.
                    Link("Experiments discussion", destination: Constants.labDiscussionURL)
                        .font(ThawType.footnote.weight(.medium))
                    Link("Discord", destination: Constants.discordURL)
                        .font(ThawType.footnote.weight(.medium))
                }
            }
        }
        .onReceive(DisplayTopology.shared.screenParametersChanged) {
            screenGeneration += 1
        }
    }

    /// One switch for all four modules: macOS hides them together, and the
    /// runtime removes each through its own Control Center preference.
    private var enableModuleStandIns: some View {
        Toggle(isOn: $settings.enableModuleStandIns) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Replace Control Center items")
                ThawBadge.alpha
            }
        }
        .annotation {
            Text(
                """
                macOS hides Focus, AirDrop, Now Playing and Fast User Switching whenever any \
                other item is hidden, even in Visible. This puts a \(Constants.displayName) icon \
                in each one's place, with its main actions in the menu, and you can move or hide \
                it like any other item. Turn this off to bring the originals back.
                """
            )
        }
    }

    /// One switch per Apple extra, with its state beneath it. The switch is
    /// what the user asked for; the status line is what is actually running,
    /// so a switch that cannot run never reads as working.
    private func systemExtraTakeoverToggle(
        _ title: LocalizedStringKey,
        isOn: Binding<Bool>,
        item: SystemExtraItem
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: ThawSpacing.compact) {
                Text(title)
                ThawBadge.alpha
            }
        }
        .annotation {
            VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                Text(
                    """
                    \(Constants.displayName) can't hide Apple's \(item.displayName) icon. \
                    This swaps it for a \(Constants.displayName) icon in the same place that does the \
                    same things and can be moved to Hidden like any other. The original comes back when you \
                    turn this off or quit \(Constants.displayName).
                    """
                )
                systemExtraTakeoverStatus(for: item)
            }
        }
    }

    @ViewBuilder
    private func systemExtraTakeoverStatus(for item: SystemExtraItem) -> some View {
        switch appState.menuBarManager.systemExtraTakeover.status(for: item).phase {
        case .off:
            EmptyView()
        case .ready:
            systemExtraStatus(
                "Starting…",
                systemImage: "circle.dashed",
                color: ThawInk.supporting
            )
        case .active:
            systemExtraStatus(
                "Replaced. \(Constants.displayName)'s icon is standing in for \(item.displayName).",
                systemImage: "checkmark.circle.fill",
                color: .green
            )
        case let .unavailable(reason), let .failed(reason):
            systemExtraStatus(reason, systemImage: "exclamationmark.triangle", color: Color.warning)
        }
    }

    private func systemExtraStatus(_ text: String, systemImage: String, color: Color) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: systemImage)
        }
        .foregroundStyle(color)
    }

    /// The status menu as a panel. Alpha: it carries only the commands with a
    /// state worth seeing, so the menu is still the complete list.
    private var enableControlItemPanel: some View {
        Toggle(isOn: $settings.enableControlItemPanel) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Panel instead of the status menu")
                ThawBadge.alpha
            }
        }
        .annotation(
            "Right-click \(Constants.displayName)’s icon to get a panel of controls instead of a menu of text.",
            more: "The panel shows the sections, Zen Mode, the active profile and the Swap Bar. Everything else stays in the menu, which comes back when this is off."
        )
    }

    private var enableMenuBarItemDescenders: some View {
        Toggle(isOn: $settings.enableMenuBarItemDescenders) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Show item details on hover")
                ThawBadge.beta
            }
        }
        .annotation {
            Text(
                """
                Hang a small readout below a menu bar item while the pointer rests on it, \
                showing what the item is already reporting in the space the menu bar has no \
                room for. Items that report nothing useful stay as they are.
                """
            )
        }
    }

    /// Custom Status Icon: an alpha persistent menu bar item composed of up to
    /// three indicators. Toggled here as an experiment; the builder opens on
    /// its own pane, which is not a sidebar destination.
    @ViewBuilder
    private var enableCustomStatusIcon: some View {
        let widget = StatusIconWidgetController.shared
        Toggle(isOn: Binding(get: { widget.isEnabled }, set: { widget.setEnabled($0) })) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Custom status icon")
                ThawBadge.beta
            }
        }
        .annotation(
            "Combine up to three indicators (battery, Wi-Fi, and more) into one menu bar icon.",
            more: "An early idea; the builder and the readings can change between releases."
        )
        // Customize is available before enabling: people can inspect their
        // design in the builder without adding it to the menu bar.
        Button("Customize…") {
            SettingsSearchNavigation.selectSidebarPane(.widgets, navigationState: appState.navigationState)
        }
        .buttonStyle(.settingsGlass)
        .controlSize(.small)
    }

    /// The toggle, plus the display pickers while it is on.
    ///
    /// The annotation states that only the mic can be attributed: macOS does
    /// not attribute the camera to any app.
    @ViewBuilder
    private var enableRecordingWatch: some View {
        Toggle(isOn: $settings.enableRecordingWatch) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Camera and microphone watch")
                ThawBadge.alpha
            }
        }
        .annotation {
            Text(
                """
                Shows a banner when an app starts using your microphone, naming the app, and \
                another when a camera turns on. macOS doesn't tell anyone which app is using a \
                camera, so that one says only that it's in use. While either is on, \
                \(Constants.displayName)'s menu lists what's using it.
                """
            )
        }
        if settings.enableRecordingWatch {
            collapseWhileRecording
            announcementScreenPicker
            announcementPlacementPicker
        }
    }

    /// Presenter mode: while the camera or microphone is in use, collapse the
    /// bar the same way Zen Mode does, and restore it when they idle.
    private var collapseWhileRecording: some View {
        Toggle(isOn: $settings.zenModeWhileRecording) {
            Text("Collapse the menu bar while recording")
        }
        .annotation {
            Text(
                """
                Enters Zen Mode while the camera or microphone is in use, so a cluttered bar \
                stays out of a screen recording or call, then restores it when recording stops. \
                Works alongside Zen Mode while presenting. While a recording is live, turning \
                Zen Mode off by hand puts it back within a second.
                """
            )
        }
    }

    /// Where along the top of that display the banners sit.
    ///
    /// Separate from the screen picker; crossing them would make nine rows.
    private var announcementPlacementPicker: some View {
        ThawPicker("Place announcements", selection: $settings.recordingWatchPlacement) {
            ForEach(ThawHUDPlacement.allCases, id: \.self) { placement in
                Text(placement.localized).tag(placement)
            }
        }
        .annotation {
            Text(
                """
                Banners appear just under the menu bar. The center is where \
                \(Constants.displayName)'s other confirmations appear; move them to a corner if \
                they land on top of what you're working on.
                """
            )
        }
    }

    /// Which display the privacy banners land on.
    ///
    /// The list is live and refreshes on display changes. An unplugged choice
    /// keeps its row, marked unavailable, so the selection survives replugging.
    private var announcementScreenPicker: some View {
        ThawPicker("Show announcements on", selection: $settings.recordingWatchScreen) {
            ForEach(announcementScreenChoices) { choice in
                Text(choice.name).tag(choice.screen)
            }
            if let unavailable = unavailableChosenDisplay {
                Text("Chosen display (unavailable)").tag(unavailable)
            }
        }
        .annotation {
            Text(
                """
                The pointer's screen follows wherever you're working. Pinning the banner to a \
                display shows it there even when the pointer is somewhere else, which is the point \
                when the camera turns on while you're not at the machine. If that display isn't \
                connected, the main display is used.
                """
            )
        }
    }

    /// One selectable row of the announcement-screen picker: a connected
    /// display by its own name, or the two fixed behaviors.
    private var announcementScreenChoices: [AnnouncementScreenChoice] {
        // Read so the body depends on it: display plug events bump this.
        _ = screenGeneration
        var choices = [
            AnnouncementScreenChoice(
                id: RecordingWatchScreen.screenWithPointer.storageKey,
                name: String(localized: "Screen with pointer"),
                screen: .screenWithPointer
            ),
            AnnouncementScreenChoice(
                id: RecordingWatchScreen.mainDisplay.storageKey,
                name: String(localized: "Main display"),
                screen: .mainDisplay
            ),
        ]
        choices += NSScreen.screens.compactMap { screen in
            guard let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) else {
                return nil
            }
            return AnnouncementScreenChoice(
                id: uuid,
                name: screen.localizedName,
                screen: .display(uuid: uuid)
            )
        }
        return choices
    }

    /// The chosen display's tag when it is no longer connected, so the
    /// picker can still show that something is selected there.
    private var unavailableChosenDisplay: RecordingWatchScreen? {
        guard case let .display(uuid) = settings.recordingWatchScreen,
              !announcementScreenChoices.contains(where: { $0.id == uuid })
        else {
            return nil
        }
        return .display(uuid: uuid)
    }

    /// The annotation admits that without Screen Recording the cover falls
    /// back to a flat average-colour patch on a translucent bar.
    private var enableDesktopMenuHiding: some View {
        Toggle(isOn: $settings.enableDesktopMenuHiding) {
            HStack(spacing: ThawSpacing.compact) {
                Text("Hide Finder menus on the desktop")
                ThawBadge.alpha
            }
        }
        .annotation {
            Text(
                """
                Clicking the desktop puts the Finder's menus in the bar. This covers them until \
                you switch to something else. The Apple menu stays, and Finder windows keep \
                their menus.

                The cover is a capture of what sits behind the bar, so it matches your wallpaper. \
                Without Screen Recording it falls back to a flat patch of the bar's average color, \
                which can show against the wallpaper.
                """
            )
        }
    }
}

/// One row of the announcement-screen picker. A struct because display cases
/// need their own names as labels.
private struct AnnouncementScreenChoice: Identifiable {
    /// Stable row identity: the screen choice's storage key, or the display
    /// UUID for a connected display.
    let id: String
    let name: String
    let screen: RecordingWatchScreen
}

#if DEBUG
    #Preview {
        TheLabSettingsPane(settings: AdvancedSettings())
            .frame(width: 600, height: 500)
    }
#endif
