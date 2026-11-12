//
//  CharacterViewerChannelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawExtraHelper

@Suite("Character Viewer channel")
struct CharacterViewerChannelTests {
    @Test("The helper names the message after its parent Thaw, as Thaw's relay listens for it")
    func messageName() throws {
        let parent = try #require(ExtraRole.parentBundleIdentifier(of: "com.example.thaw.extra.textinput"))
        #expect(CharacterViewerChannel.notification(parent: parent).rawValue == "com.example.thaw.extra.characterViewer")
    }
}
