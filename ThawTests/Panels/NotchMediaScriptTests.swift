//
//  NotchMediaScriptTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

struct NotchMediaScriptTests {
    @Test
    func currentTrackQueryIsBoundedToOneSecond() {
        let script = NotchMediaScript.script(for: .currentTrack, of: .spotify)
        #expect(script?.source == "with timeout of 1 second\ntell application \"Spotify\" to get {name, artist} of current track\nend timeout")
    }

    @Test
    func playerStateQueryTargetsTheChosenPlayer() {
        let script = NotchMediaScript.script(for: .playerState, of: .music)
        #expect(script?.source == "with timeout of 1 second\ntell application \"Music\" to get player state\nend timeout")
    }

    @Test(arguments: [
        (NotchMediaScript.Command.play, "play"),
        (.pause, "pause"),
        (.nextTrack, "next track"),
        (.previousTrack, "previous track"),
    ])
    func commandsUseTheDictionaryVerb(command: NotchMediaScript.Command, verb: String) {
        let script = NotchMediaScript.script(for: command, of: .spotify)
        #expect(script?.source == "tell application \"Spotify\" to \(verb)")
    }

    @Test
    func playersAreTheTwoSupportedApps() {
        #expect(NotchMediaScript.Player.allCases.map(\.rawValue) == ["Spotify", "Music"])
    }

    @Test("Every script names the player it is for and only ever one of the fixed requests", arguments: NotchMediaScript.Player.allCases)
    func everyScriptTargetsItsPlayer(player: NotchMediaScript.Player) {
        let reads = NotchMediaScript.Query.allCases.compactMap { NotchMediaScript.script(for: $0, of: player)?.source }
        let commands = NotchMediaScript.Command.allCases.compactMap { NotchMediaScript.script(for: $0, of: player)?.source }
        let tell = "tell application \"\(player.rawValue)\" to "
        #expect(reads == [
            "with timeout of 1 second\n\(tell)get {name, artist} of current track\nend timeout",
            "with timeout of 1 second\n\(tell)get player state\nend timeout",
        ])
        #expect(commands == ["play", "pause", "next track", "previous track"].map { tell + $0 })
    }
}
