//
//  WindowInfoTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing

@Suite("Window information")
struct WindowInfoTests {
    @Test("Coding preserves every field")
    func codingPreservesEveryField() throws {
        let original = try makeWindowInfo(
            windowID: 99999,
            ownerPID: 5555,
            bounds: CGRect(x: 100, y: 200, width: 300, height: 400),
            layer: 42,
            title: nil,
            ownerName: nil,
            isOnScreen: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowInfo.self, from: data)

        #expect(decoded == original)
        #expect(decoded.title == nil)
        #expect(decoded.ownerName == nil)
    }

    @Test("Equality and hashing include every field")
    func equalityAndHashingIncludeEveryField() throws {
        let baseline = try makeWindowInfo()
        let duplicate = try makeWindowInfo()
        let variants = try [
            makeWindowInfo(windowID: 1),
            makeWindowInfo(ownerPID: 2),
            makeWindowInfo(bounds: CGRect(x: 1, y: 2, width: 3, height: 4)),
            makeWindowInfo(layer: 1),
            makeWindowInfo(title: nil),
            makeWindowInfo(ownerName: nil),
            makeWindowInfo(isOnScreen: false),
        ]

        #expect(baseline == duplicate)
        #expect(Set([baseline, duplicate]).count == 1)
        for variant in variants {
            #expect(variant != baseline)
        }
    }

    @Test("Window Server ownership is recognized")
    func windowServerOwnershipIsRecognized() throws {
        #expect(try makeWindowInfo(ownerName: "Window Server").isWindowServerWindow)
        #expect(try !makeWindowInfo(ownerName: "SomeApp").isWindowServerWindow)
        #expect(try !makeWindowInfo(ownerName: nil).isWindowServerWindow)
    }

    @Test("Menu-related window levels are recognized")
    func menuRelatedWindowLevelsAreRecognized() throws {
        let menuLevels = [
            CGWindowLevelForKey(.mainMenuWindow),
            CGWindowLevelForKey(.statusWindow),
            CGWindowLevelForKey(.popUpMenuWindow),
            CGWindowLevelForKey(.popUpMenuWindow) - 1,
        ]

        for level in menuLevels {
            #expect(try makeWindowInfo(layer: Int(level)).isMenuRelated)
        }
        #expect(try makeWindowInfo(layer: 0).isMenuRelated == false)
        #expect(try makeWindowInfo(layer: 0, ownerName: "Window Server").isMenuRelated)
    }

    private func makeWindowInfo(
        windowID: CGWindowID = 12345,
        ownerPID: pid_t = 1000,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 100, height: 22),
        layer: Int = 25,
        title: String? = "TestItem",
        ownerName: String? = "TestApp",
        isOnScreen: Bool = true
    ) throws -> WindowInfo {
        let titleJSON = title.map { "\"\($0)\"" } ?? "null"
        let ownerNameJSON = ownerName.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
            "windowID": \(windowID),
            "ownerPID": \(ownerPID),
            "bounds": [[\(bounds.origin.x), \(bounds.origin.y)], [\(bounds.size.width), \(bounds.size.height)]],
            "layer": \(layer),
            "title": \(titleJSON),
            "ownerName": \(ownerNameJSON),
            "isOnScreen": \(isOnScreen)
        }
        """
        return try JSONDecoder().decode(WindowInfo.self, from: Data(json.utf8))
    }
}
