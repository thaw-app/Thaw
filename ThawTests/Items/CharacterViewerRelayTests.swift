//
//  CharacterViewerRelayTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// The message the Text Input stand-in sends for "Show Emoji & Symbols", and the shortcut Thaw presses for it.
/// Nothing here is posted.
@MainActor
@Suite("Character Viewer relay")
struct CharacterViewerRelayTests {
    @Test("The message is named after the Thaw that started the stand-in, as the helper names it")
    func messageName() {
        #expect(CharacterViewerRelay.notification(parent: "com.example.thaw").rawValue == "com.example.thaw.extra.characterViewer")
        #expect(
            CharacterViewerRelay.notification(parent: ThawMenuBarIdentity.bundleIdentifier)
                != ExtraVisibilityChannel.notification,
            "it never reaches the visibility listeners"
        )
    }

    @Test("Thaw presses and releases ⌃⌘Space")
    func pressesTheShortcut() throws {
        let events = CharacterViewerRelay.shortcutEvents()
        try #require(events.count == 2)
        #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [49, 49])
        #expect(events.map(\.type) == [.keyDown, .keyUp])
        for event in events {
            #expect(event.flags.contains(.maskControl) && event.flags.contains(.maskCommand))
            #expect(!event.flags.contains(.maskShift) && !event.flags.contains(.maskAlternate))
        }
    }

    @Test("A request is answered only while the stand-in runs, right after real input, and once a second")
    func answersOnlyRealRequests() {
        #expect(CharacterViewerRelay.answers(standInIsRunning: true, secondsSinceInput: 0.1, sinceLastOpen: nil))
        #expect(CharacterViewerRelay.answers(standInIsRunning: true, secondsSinceInput: 0.1, sinceLastOpen: .seconds(2)))
        #expect(!CharacterViewerRelay.answers(standInIsRunning: false, secondsSinceInput: 0.1, sinceLastOpen: nil), "no stand-in asked")
        #expect(!CharacterViewerRelay.answers(standInIsRunning: true, secondsSinceInput: 5, sinceLastOpen: nil), "nobody clicked or typed")
        #expect(!CharacterViewerRelay.answers(standInIsRunning: true, secondsSinceInput: 0.1, sinceLastOpen: .milliseconds(200)), "too soon after the last")
    }
}
