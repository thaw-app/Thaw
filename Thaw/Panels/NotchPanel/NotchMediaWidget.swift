//
//  NotchMediaWidget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// Transport controls and track info, descending from a media player's own
/// menu bar item.
///
/// The player is whichever one the hovered item belongs to, not whichever
/// happens to be running: the descender hangs under Spotify's item because it
/// is about Spotify.
///
/// Both players are driven through their published AppleScript dictionaries,
/// public interfaces, no private frameworks, no new entitlements. The first
/// command triggers macOS's standard Automation consent dialog; the user can
/// revoke it in System Settings. Data refreshes only while the descender is
/// showing, or right after a command, never in the background.
@MainActor
@Observable
final class NotchMediaWidget: NotchWidget {
    let id = "media"
    let refreshPolicy: NotchWidgetRefreshPolicy = .whileRevealed
    let bodySize = CGSize(width: 268, height: 88)

    /// Scripting targets, keyed by the bundle identifier of the menu bar item
    /// they own.
    private static let supportedApps: [String: NotchMediaScript.Player] = [
        "com.spotify.client": .spotify,
        "com.apple.Music": .music,
    ]

    private(set) var trackTitle: String?
    private(set) var trackArtist: String?
    private(set) var isPlaying = false

    /// The player the current descender is about.
    private var player: NotchMediaScript.Player?

    /// The player's display name, shown when no track is playing.
    private var appName: String? {
        player?.rawValue
    }

    func matches(_ item: MenuBarItem) -> Bool {
        guard case let .string(bundleID) = item.tag.namespace else {
            return false
        }
        return Self.supportedApps[bundleID] != nil
    }

    func prepare(for item: MenuBarItem) {
        guard case let .string(bundleID) = item.tag.namespace else {
            player = nil
            return
        }
        let newPlayer = Self.supportedApps[bundleID]
        if newPlayer != player {
            trackTitle = nil
            trackArtist = nil
            isPlaying = false
        }
        player = newPlayer
    }

    func isAvailable() -> Bool {
        player != nil
    }

    // MARK: View

    var body: AnyView {
        AnyView(WidgetBody(widget: self))
    }

    /// The transport as a real view, so that reading the widget establishes a
    /// dependency on it.
    ///
    /// Assembled inline, this was a snapshot taken whenever the panel happened
    /// to rebuild: nothing observed the widget, so pressing play or pause
    /// updated isPlaying and left the glyph showing the old state until
    /// something unrelated invalidated the panel. Revealing the descender only
    /// appeared to work because it changes the panel's own state first.
    private struct WidgetBody: View {
        let widget: NotchMediaWidget

        var body: some View {
            VStack(spacing: 8) {
                VStack(spacing: 1) {
                    Text(widget.trackTitle ?? "Nothing Playing")
                        .font(ThawType.body.weight(.semibold))
                        .lineLimit(1)
                    Text(widget.trackArtist ?? widget.appName ?? "")
                        .font(ThawType.caption)
                        .foregroundStyle(ThawInk.supporting)
                        .lineLimit(1)
                }
                HStack(spacing: 22) {
                    transportButton("backward.fill", label: "Previous Track") { widget.command(.previousTrack) }
                    transportButton(
                        widget.isPlaying ? "pause.fill" : "play.fill",
                        label: widget.isPlaying ? "Pause" : "Play"
                    ) {
                        widget.command(widget.isPlaying ? .pause : .play)
                    }
                    transportButton("forward.fill", label: "Next Track") { widget.command(.nextTrack) }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func transportButton(
            _ symbol: String,
            label: LocalizedStringKey,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(ThawType.symbol.weight(.medium))
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .help(label)
            .accessibilityLabel(label)
        }
    }

    // MARK: Commands and refresh

    func refresh() {
        guard let player else {
            trackTitle = nil
            trackArtist = nil
            isPlaying = false
            return
        }

        if let parts = runAppleScript({
            NotchMediaScript.script(for: .currentTrack, of: player)
        })?.stringValue?.split(separator: "\", \"").map(String.init), parts.count == 2 {
            trackTitle = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            trackArtist = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        } else {
            trackTitle = nil
            trackArtist = nil
        }

        isPlaying = runAppleScript({
            NotchMediaScript.script(for: .playerState, of: player)
        })?.stringValue == "playing"
    }

    /// Runs one playback command against the player this descender is about,
    /// then refreshes so the view reflects the new state immediately.
    private func command(_ command: NotchMediaScript.Command) {
        guard let player else { return }
        _ = runAppleScript { NotchMediaScript.script(for: command, of: player) }
        refresh()
    }

    /// Makes and executes an AppleScript on the main thread, where NSAppleScript must be used.
    /// First use triggers macOS's standard Automation consent dialog for the target app.
    private nonisolated func runAppleScript(_ makeScript: @Sendable () -> NSAppleScript?) -> NSAppleEventDescriptor? {
        guard Thread.isMainThread else {
            return DispatchQueue.main.sync {
                self.runAppleScript(makeScript)
            }
        }
        var error: NSDictionary?
        return makeScript()?.executeAndReturnError(&error)
    }
}
