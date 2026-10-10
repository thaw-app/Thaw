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

/// The wallpaper backdrop the preview bar sits on, centered. Without a
/// wallpaper (the new-display template or a disconnected display) a neutral
/// fill stands in.
struct ThawBarPreviewStage<Content: View>: View {
    @Environment(AppState.self) private var appState
    let displayID: CGDirectDisplayID?
    @ViewBuilder let content: Content

    @State private var wallpaperImage: NSImage?

    private let minHeight: CGFloat = 120
    /// Room between the bar and the stage edge, so wallpaper shows all around.
    private let margin: CGFloat = 28

    var body: some View {
        content
            .padding(margin)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background {
                if let wallpaperImage {
                    // The top of the wallpaper is what sits behind the real
                    // bar, so crop from there rather than the middle.
                    Image(nsImage: wallpaperImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous))
            // The sampled bar colour changes with the wallpaper, so it doubles
            // as the refresh signal; the display ID alone never changed.
            .task(id: RefreshKey(displayID: displayID, sample: displayID.flatMap { appState.menuBarManager.averageColors[$0]?.color })) {
                wallpaperImage = await wallpaperImage(for: displayID)
            }
    }

    private struct RefreshKey: Equatable {
        let displayID: CGDirectDisplayID?
        let sample: CGColor?
    }

    /// The top of what lies under the selected display's menu bar, or nil
    /// for the template or a disconnected display.
    ///
    /// Composited from the desktop-level windows rather than read from the
    /// wallpaper file, so a live wallpaper shows; app windows, Settings
    /// included, are left out.
    private func wallpaperImage(for displayID: CGDirectDisplayID?) async -> NSImage? {
        guard let displayID, let screen = NSScreen.screen(for: displayID) else {
            return nil
        }
        let frame = screen.cgFrame
        let band = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(frame.height, 240))
        if let image = await appState.menuBarManager.backdrop.capture(band, belowLayer: Int(kCGNormalWindowLevel)) {
            return NSImage(cgImage: image, size: band.size)
        }
        return NSWorkspace.shared.desktopImageURL(for: screen).flatMap(NSImage.init(contentsOf:))
    }
}

/// What the preview shows, and the control that opens the real bar.
struct ThawBarPreviewFooter: View {
    @Environment(AppState.self) private var appState
    let useThawBar: Bool
    let displayID: CGDirectDisplayID?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.inset) {
            caption
            Spacer(minLength: ThawSpacing.base)
            openControl
        }
    }

    private var caption: some View {
        Text(captionText)
            .font(.caption)
            .foregroundStyle(ThawInk.supporting)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captionText: LocalizedStringKey {
        if let displayID, displayIsConnected(displayID) {
            return useThawBar
                ? "Preview uses the current hidden section. Open the real \(Constants.displayName) Bar to use it."
                : "Preview uses the current hidden section. The \(Constants.displayName) Bar is off on this display."
        }
        return "Preview uses the current hidden section. The real \(Constants.displayName) Bar opens on a connected display."
    }

    @ViewBuilder
    private var openControl: some View {
        if let displayID, displayIsConnected(displayID) {
            if useThawBar {
                Button("Open \(Constants.displayName) Bar") {
                    openThawBar(on: displayID)
                }
                .buttonStyle(.settingsGlass)
                .controlSize(.small)
            } else {
                Button("Enable & Open") {
                    enableAndOpen(on: displayID)
                }
                .buttonStyle(.settingsGlass)
                .controlSize(.small)
            }
        } else if displayID != nil {
            // Disconnected display: explain rather than claim to open.
            Text("Reconnect this display to open the \(Constants.displayName) Bar.")
                .font(.caption)
                .foregroundStyle(ThawInk.supporting)
        } else {
            // Template: no display to open on.
            Text("Pick a connected display to open the \(Constants.displayName) Bar.")
                .font(.caption)
                .foregroundStyle(ThawInk.supporting)
        }
    }

    private func openThawBar(on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screen(for: displayID) else {
            return
        }
        appState.menuBarManager.thawBarPanel.show(section: .hidden, on: screen)
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
