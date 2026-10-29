//
//  NotchMediaScript.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// The AppleScripts the media descender runs.
///
/// Every script is made from a complete string literal picked by player and request,
/// so nothing read from outside, such as a bundle ID or a track title, reaches one.
nonisolated enum NotchMediaScript {
    /// A player the descender can drive, with its scripting name.
    enum Player: String, CaseIterable, Sendable {
        case spotify = "Spotify"
        case music = "Music"
    }

    /// A value the descender reads from the player.
    enum Query: CaseIterable, Sendable {
        case currentTrack
        case playerState
    }

    /// A transport command sent to the player.
    enum Command: CaseIterable, Sendable {
        case play
        case pause
        case nextTrack
        case previousTrack
    }

    /// A read, bounded to one second so a busy player cannot stall the panel.
    static func script(for query: Query, of player: Player) -> NSAppleScript? {
        switch (query, player) {
        case (.currentTrack, .spotify):
            NSAppleScript(source: "with timeout of 1 second\ntell application \"Spotify\" to get {name, artist} of current track\nend timeout")
        case (.currentTrack, .music):
            NSAppleScript(source: "with timeout of 1 second\ntell application \"Music\" to get {name, artist} of current track\nend timeout")
        case (.playerState, .spotify):
            NSAppleScript(source: "with timeout of 1 second\ntell application \"Spotify\" to get player state\nend timeout")
        case (.playerState, .music):
            NSAppleScript(source: "with timeout of 1 second\ntell application \"Music\" to get player state\nend timeout")
        }
    }

    static func script(for command: Command, of player: Player) -> NSAppleScript? {
        switch (command, player) {
        case (.play, .spotify): NSAppleScript(source: "tell application \"Spotify\" to play")
        case (.play, .music): NSAppleScript(source: "tell application \"Music\" to play")
        case (.pause, .spotify): NSAppleScript(source: "tell application \"Spotify\" to pause")
        case (.pause, .music): NSAppleScript(source: "tell application \"Music\" to pause")
        case (.nextTrack, .spotify): NSAppleScript(source: "tell application \"Spotify\" to next track")
        case (.nextTrack, .music): NSAppleScript(source: "tell application \"Music\" to next track")
        case (.previousTrack, .spotify): NSAppleScript(source: "tell application \"Spotify\" to previous track")
        case (.previousTrack, .music): NSAppleScript(source: "tell application \"Music\" to previous track")
        }
    }
}
