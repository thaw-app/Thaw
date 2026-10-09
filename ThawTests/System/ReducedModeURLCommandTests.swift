//
//  ReducedModeURLCommandTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct ReducedModeURLCommandTests {
    private func command(_ string: String) throws -> ReducedModeURLCommand? {
        try ReducedModeURLCommand(#require(URL(string: string)))
    }

    @Test
    func `reads each request the reduced mode answers`() throws {
        #expect(try command("thaw://toggle-hidden") == .toggleHidden)
        #expect(try command("thaw://list-apps") == .listApps)
        #expect(try command("thaw://hide-app?bundle=com.example.a") == .hideApp("com.example.a"))
        #expect(try command("thaw://show-app?bundle=com.example.a") == .showApp("com.example.a"))
    }

    @Test
    func `ignores the case of the request's name`() throws {
        #expect(try command("thaw://Toggle-Hidden") == .toggleHidden)
    }

    @Test
    func `refuses a hide or show that names no app`() throws {
        #expect(try command("thaw://hide-app") == nil)
        #expect(try command("thaw://show-app?bundle=") == nil)
        #expect(try command("thaw://hide-app?app=com.example.a") == nil)
    }

    @Test
    func `refuses the full app's requests`() throws {
        for request in ["open-settings", "set?key=showOnHover&value=true", "toggle-thawbar", "search", "dump-items"] {
            #expect(try command("thaw://\(request)") == nil)
        }
    }
}
