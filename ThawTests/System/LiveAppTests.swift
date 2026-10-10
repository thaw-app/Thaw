//
//  LiveAppTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
struct LiveAppTests {
    @Test
    func `the running app's state can be reached, which is what every intent needs`() {
        #expect(LiveApp.delegate != nil)
        #expect(LiveApp.appState != nil)
        #expect(thawAppState() != nil)
    }

    @Test
    func `NSApp's delegate is SwiftUI's, not Thaw's, so it must not be used to find the app`() {
        // The reason LiveApp exists. If this ever starts passing a cast, the lookup could be simplified.
        #expect((NSApp?.delegate as? AppDelegate) == nil)
    }
}
