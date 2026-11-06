//
//  NotchReadoutWidgetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import SwiftUI
import Testing
@testable import Thaw

/// An item with no bundle namespace, which no descender is about.
@MainActor
private var untaggedItem: MenuBarItem {
    MenuBarItem(
        tag: MenuBarItemTag(namespace: .null, title: "Untagged", instanceIndex: 0),
        windowID: 0xFFFF_FF01, ownerPID: 0, sourcePID: 0,
        bounds: CGRect(x: 0, y: 0, width: 24, height: 24), title: nil, isOnScreen: true
    )
}

/// Answers the media widget's scripts the way a player would, recording what was sent.
@MainActor
private final class FakePlayer {
    var track: String? = "\"Blue in Green\", \"Miles Davis\""
    var state = "paused"
    private(set) var sources = [String]()

    func run(_ script: NSAppleScript) -> String? {
        let source = script.source ?? ""
        sources.append(source)
        if source.contains("current track") {
            return track
        }
        if source.contains("player state") {
            return state
        }
        if source.hasSuffix(" to play") {
            state = "playing"
        } else if source.hasSuffix(" to pause") {
            state = "paused"
        }
        return nil
    }
}

@Suite("Notch media widget with a player")
@MainActor
struct NotchMediaPlayerTests {
    private func widget(_ player: FakePlayer, bundleID: String = "com.spotify.client") -> NotchMediaWidget {
        let widget = NotchMediaWidget(execute: player.run)
        widget.prepare(for: NotchFixtures.item(bundleID: bundleID, title: "Player"))
        return widget
    }

    @Test("Refreshing reads the track and artist without their quotes, and the playing state")
    func refreshReadsTheTrack() {
        let player = FakePlayer()
        player.state = "playing"
        let widget = widget(player)
        widget.refresh()
        #expect(widget.trackTitle == "Blue in Green")
        #expect(widget.trackArtist == "Miles Davis")
        #expect(widget.isPlaying)
        #expect(player.sources.allSatisfy { $0.contains("\"Spotify\"") })
    }

    @Test("Scripts go to the player whose item was prepared")
    func scriptsTargetThePreparedPlayer() {
        let player = FakePlayer()
        widget(player, bundleID: "com.apple.Music").refresh()
        #expect(!player.sources.isEmpty)
        #expect(player.sources.allSatisfy { $0.contains("\"Music\"") })
    }

    @Test("A reply that is not a title and artist pair clears the track", arguments: [nil, "Only a title", "\"a\", \"b\", \"c\""])
    func malformedTrackClears(reply: String?) {
        let player = FakePlayer()
        let widget = widget(player)
        widget.refresh()
        #expect(widget.trackTitle != nil)
        player.track = reply
        widget.refresh()
        #expect(widget.trackTitle == nil)
        #expect(widget.trackArtist == nil)
        #expect(!widget.isPlaying)
    }

    @Test("A command is sent to the player and the widget refreshes right after")
    func commandRefreshes() {
        let player = FakePlayer()
        let widget = widget(player)
        widget.command(.play)
        #expect(player.sources.first == "tell application \"Spotify\" to play")
        #expect(widget.isPlaying)
        #expect(widget.trackTitle == "Blue in Green")
        widget.command(.pause)
        #expect(!widget.isPlaying)
    }

    @Test("Without a player a command sends nothing")
    func commandWithoutPlayer() {
        let player = FakePlayer()
        let widget = NotchMediaWidget(execute: player.run)
        widget.command(.play)
        #expect(player.sources.isEmpty)
    }

    @Test("Switching players forgets the previous player's track")
    func switchingPlayersClears() {
        let player = FakePlayer()
        player.state = "playing"
        let widget = widget(player)
        widget.refresh()
        widget.prepare(for: NotchFixtures.item(bundleID: "com.apple.Music", title: "Music"))
        #expect(widget.trackTitle == nil)
        #expect(!widget.isPlaying)
        widget.prepare(for: untaggedItem)
        #expect(!widget.matches(untaggedItem))
        #expect(!widget.isAvailable(), "an item without a bundle namespace has no player")
    }

    private func pixels(of widget: NotchMediaWidget) throws -> Data {
        try OffscreenRender(widget.body.frame(width: widget.bodySize.width, height: widget.bodySize.height), size: widget.bodySize).pixels()
    }

    @Test("The body redraws for the track and for the playing state")
    func bodyFollowsTheTrackAndState() throws {
        let player = FakePlayer()
        let widget = widget(player)
        let nothing = try pixels(of: widget)
        widget.refresh()
        let paused = try pixels(of: widget)
        widget.command(.play)
        let playing = try pixels(of: widget)
        #expect(paused != nothing, "the track replaces Nothing Playing")
        #expect(playing != paused, "Pause replaces the Play glyph")
        widget.command(.pause)
        #expect(try pixels(of: widget) == paused)
    }
}

@Suite("Notch accessory widget readouts")
@MainActor
struct NotchAccessoryReadoutTests {
    private static var weather: MenuBarItem {
        NotchFixtures.item(bundleID: "com.example.weather", title: "Weather")
    }

    @Test("A readout fills the detail, a second line and the condition's glyph")
    func readoutFillsTheWidget() {
        let widget = NotchAccessoryWidget { _ in ["Partly Cloudy", nil, "72 degrees in Lisbon", nil, "Weather"] }
        widget.prepare(for: Self.weather)
        #expect(widget.isAvailable())
        #expect(widget.detail == "Partly Cloudy")
        #expect(widget.secondary == "72 degrees in Lisbon")
        #expect(widget.symbolName == "cloud.sun.fill")
    }

    private static func measure(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).size().width)
    }

    @Test("The body is as wide as its padding, detail, glyph and second line")
    func bodyWidthAddsEachPart() {
        func size(_ candidates: [String?]) -> CGSize {
            let widget = NotchAccessoryWidget { _ in candidates }
            widget.prepare(for: Self.weather)
            return widget.bodySize
        }
        let detail = "Garage door left open"
        let rainy = "Garage door open, rain"
        let second = "Battery at 80 percent"
        let detailWidth = Self.measure(detail, size: 13, weight: .medium)
        #expect(size([detail]).width == 32 + detailWidth)
        #expect(size([rainy]).width == 32 + Self.measure(rainy, size: 13, weight: .medium) + 7 + 17)
        #expect(size([detail, second]).width == 32 + detailWidth + 7 + Self.measure(second, size: 12, weight: .regular))
        #expect(size([String(repeating: "Long readout ", count: 40)]) == CGSize(width: 380, height: 34))
    }

    @Test("A candidate that only repeats the item's title or a part of its bundle ID is not a readout", arguments: ["Weather", "example", "com"])
    func namesAreNotReadouts(candidate: String) {
        let widget = NotchAccessoryWidget { _ in [candidate] }
        widget.prepare(for: Self.weather)
        #expect(!widget.isAvailable())
    }

    @Test("An item with no bundle namespace gets no readout")
    func untaggedItemDoesNotMatch() {
        #expect(!NotchAccessoryWidget { _ in ["Garage door open"] }.matches(untaggedItem))
    }

    @Test("An item that cannot be read leaves the previous readout cleared")
    func unreadableItemClears() {
        var candidates: [String?]? = ["Thunderstorms likely"]
        let widget = NotchAccessoryWidget { _ in candidates }
        widget.prepare(for: Self.weather)
        #expect(widget.symbolName == "cloud.bolt.fill")
        candidates = nil
        widget.prepare(for: Self.weather)
        #expect(widget.detail == nil)
        #expect(widget.secondary == nil)
        #expect(widget.symbolName == nil)
    }

    @Test("The body draws the second line after the detail and its glyph")
    func bodyDrawsEachPart() throws {
        func pixels(_ candidates: [String?]) throws -> Data {
            let widget = NotchAccessoryWidget { _ in candidates }
            widget.prepare(for: Self.weather)
            let size = CGSize(width: 380, height: 34)
            return try OffscreenRender(widget.body.frame(width: size.width, height: size.height), size: size).pixels()
        }
        let detail = try pixels(["Light rain"])
        #expect(detail.contains { $0 != 0 })
        let withSecond = try pixels(["Light rain", "Battery at 80 percent"])
        #expect(withSecond != detail)
        #expect(try pixels(["Light rain", "Battery at 20 percent"]) != withSecond, "the second line's own text is drawn")
    }
}
