//
//  ThawBarPreviewParts.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import ThawUI

/// The backdrop the preview bar sits on: the colour sampled from that display's menu bar, as the
/// Layout bars use. The template and a disconnected display have no sample and get a neutral fill.
struct ThawBarPreviewStage<Content: View>: View {
    @Environment(AppState.self) private var appState
    let displayID: CGDirectDisplayID?
    @ViewBuilder let content: Content

    private let minHeight: CGFloat = 120
    /// Room between the bar and the stage edge, so the backdrop shows all around.
    private let margin: CGFloat = 28

    var body: some View {
        content
            .padding(margin)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                if let sample = displayID.flatMap({ appState.menuBarManager.averageColors[$0]?.color }) {
                    Rectangle().fill(Color(cgColor: sample))
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
    }
}

/// What the preview shows, and the control that opens the real bar.
struct ThawBarPreviewFooter: View {
    @Environment(AppState.self) private var appState
    let useThawBar: Bool
    let displayID: CGDirectDisplayID?
    var alwaysHiddenOnly = false

    /// The preview button opens the section that uses the bar without enabling Hidden.
    var sectionToOpen: MenuBarSection.Name {
        alwaysHiddenOnly ? .alwaysHidden : .hidden
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.inset) {
            caption
            Spacer(minLength: ThawSpacing.base)
            openControl
        }
    }

    private var caption: some View {
        Text(captionText)
            .font(ThawType.caption)
            .foregroundStyle(ThawInk.supporting)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captionText: LocalizedStringKey {
        if let displayID, displayIsConnected(displayID) {
            if alwaysHiddenOnly {
                return "Preview uses the current Always Hidden section. Open the real \(Constants.displayName) Bar to use it."
            }
            return useThawBar
                ? "Preview uses the current hidden section. Open the real \(Constants.displayName) Bar to use it."
                : "Preview uses the current hidden section. The \(Constants.displayName) Bar is off on this display."
        }
        return alwaysHiddenOnly
            ? "Preview uses the current Always Hidden section. The real \(Constants.displayName) Bar opens on a connected display."
            : "Preview uses the current hidden section. The real \(Constants.displayName) Bar opens on a connected display."
    }

    @ViewBuilder
    private var openControl: some View {
        if let displayID, displayIsConnected(displayID) {
            if useThawBar || alwaysHiddenOnly {
                Button("Open \(Constants.displayName) Bar") {
                    openThawBar(on: displayID)
                }
                .buttonStyle(.settingsGlass)
            } else {
                Button("Turn On & Open") {
                    enableAndOpen(on: displayID)
                }
                .buttonStyle(.settingsGlass)
            }
        } else if displayID != nil {
            // Disconnected display: explain rather than claim to open.
            Text("Reconnect this display to open the \(Constants.displayName) Bar.")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
        } else {
            // Template: no display to open on.
            Text("Pick a connected display to open the \(Constants.displayName) Bar.")
                .font(ThawType.caption)
                .foregroundStyle(ThawInk.supporting)
        }
    }

    private func openThawBar(on displayID: CGDirectDisplayID) {
        ThawBarSettingsLink.openBar(
            sectionToOpen,
            on: displayID,
            settings: appState.settings.displaySettings,
            show: ThawBarSettingsLink.showsBar(of: appState)
        )
    }

    /// Enables the Thaw Bar on the display, then opens it. Mirrors what the
    /// "Use Thaw Bar" toggle does, so the preview never enables silently: the
    /// control says "Enable" out loud.
    private func enableAndOpen(on displayID: CGDirectDisplayID) {
        guard let uuid = Bridging.getDisplayUUIDString(for: displayID) else {
            return
        }
        appState.settings.displaySettings.updateConfiguration(forDisplayUUID: uuid) {
            $0.withUseThawBar(true)
        }
        openThawBar(on: displayID)
    }

    private func displayIsConnected(_ displayID: CGDirectDisplayID) -> Bool {
        NSScreen.screens.contains(where: { $0.displayID == displayID })
    }
}
