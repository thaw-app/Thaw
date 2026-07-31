//
//  WindowInfoTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@Suite("Window info")
struct WindowInfoTests {
    // MARK: - Test Helpers

    private func createWindowInfo(
        windowID: CGWindowID = 12345,
        ownerPID: pid_t = 1000,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 100, height: 22),
        layer: Int = 25,
        title: String? = "TestItem",
        ownerName: String? = "TestApp",
        isOnScreen: Bool = true
    ) -> WindowInfo {
        // CGRect encodes as nested arrays: [[x,y],[width,height]]
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
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(WindowInfo.self, from: data)
    }

    // MARK: - Codable Tests

    @Test("A window survives an encode/decode round trip")
    func encodeDecode() throws {
        let original = createWindowInfo()

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WindowInfo.self, from: data)

        #expect(decoded.windowID == original.windowID)
        #expect(decoded.ownerPID == original.ownerPID)
        #expect(decoded.bounds == original.bounds)
        #expect(decoded.layer == original.layer)
        #expect(decoded.title == original.title)
        #expect(decoded.ownerName == original.ownerName)
        #expect(decoded.isOnScreen == original.isOnScreen)
    }

    @Test("A nil title stays nil across a round trip")
    func decodeWithNilTitle() throws {
        let window = createWindowInfo(title: nil)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(window)
        let decoded = try decoder.decode(WindowInfo.self, from: data)

        #expect(decoded.title == nil)
    }

    @Test("A nil owner name stays nil across a round trip")
    func decodeWithNilOwnerName() throws {
        let window = createWindowInfo(ownerName: nil)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(window)
        let decoded = try decoder.decode(WindowInfo.self, from: data)

        #expect(decoded.ownerName == nil)
    }

    @Test("Every field survives a round trip with its own value")
    func decodePreservesAllFields() throws {
        let original = createWindowInfo(
            windowID: 99999,
            ownerPID: 5555,
            bounds: CGRect(x: 100, y: 200, width: 300, height: 400),
            layer: 42,
            title: "SpecificTitle",
            ownerName: "SpecificApp",
            isOnScreen: false
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WindowInfo.self, from: data)

        #expect(decoded.windowID == 99999)
        #expect(decoded.ownerPID == 5555)
        #expect(decoded.bounds.origin.x == 100)
        #expect(decoded.bounds.origin.y == 200)
        #expect(decoded.bounds.size.width == 300)
        #expect(decoded.bounds.size.height == 400)
        #expect(decoded.layer == 42)
        #expect(decoded.title == "SpecificTitle")
        #expect(decoded.ownerName == "SpecificApp")
        #expect(!decoded.isOnScreen)
    }

    // MARK: - Equatable Tests

    @Test("Two identically built windows are equal")
    func equalityIdentical() {
        let window1 = createWindowInfo()
        let window2 = createWindowInfo()

        #expect(window1 == window2)
    }

    @Test("A different window ID breaks equality")
    func equalityDifferentWindowID() {
        let window1 = createWindowInfo(windowID: 1)
        let window2 = createWindowInfo(windowID: 2)

        #expect(window1 != window2)
    }

    @Test("A different owner PID breaks equality")
    func equalityDifferentOwnerPID() {
        let window1 = createWindowInfo(ownerPID: 100)
        let window2 = createWindowInfo(ownerPID: 200)

        #expect(window1 != window2)
    }

    @Test("Different bounds break equality")
    func equalityDifferentBounds() {
        let window1 = createWindowInfo(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        let window2 = createWindowInfo(bounds: CGRect(x: 10, y: 10, width: 100, height: 100))

        #expect(window1 != window2)
    }

    @Test("A different layer breaks equality")
    func equalityDifferentLayer() {
        let window1 = createWindowInfo(layer: 10)
        let window2 = createWindowInfo(layer: 20)

        #expect(window1 != window2)
    }

    @Test("A different title breaks equality")
    func equalityDifferentTitle() {
        let window1 = createWindowInfo(title: "Title1")
        let window2 = createWindowInfo(title: "Title2")

        #expect(window1 != window2)
    }

    @Test("A different owner name breaks equality")
    func equalityDifferentOwnerName() {
        let window1 = createWindowInfo(ownerName: "App1")
        let window2 = createWindowInfo(ownerName: "App2")

        #expect(window1 != window2)
    }

    @Test("A different on-screen flag breaks equality")
    func equalityDifferentIsOnScreen() {
        let window1 = createWindowInfo(isOnScreen: true)
        let window2 = createWindowInfo(isOnScreen: false)

        #expect(window1 != window2)
    }

    @Test("A nil title is not equal to a present one")
    func equalityNilVsNonNilTitle() {
        let window1 = createWindowInfo(title: nil)
        let window2 = createWindowInfo(title: "SomeTitle")

        #expect(window1 != window2)
    }

    // MARK: - Hashable Tests

    @Test("Equal windows hash equally")
    func hashableConsistency() {
        let window1 = createWindowInfo()
        let window2 = createWindowInfo()

        #expect(window1.hashValue == window2.hashValue)
    }

    @Test("A set deduplicates equal windows")
    func hashableInSet() {
        let window1 = createWindowInfo(windowID: 1)
        let window2 = createWindowInfo(windowID: 2)
        let window3 = createWindowInfo(windowID: 1) // duplicate of window1

        var set = Set<WindowInfo>()
        set.insert(window1)
        set.insert(window2)
        set.insert(window3)

        #expect(set.count == 2)
    }

    @Test("A window works as a dictionary key")
    func hashableAsDictionaryKey() {
        let window = createWindowInfo()
        var dict = [WindowInfo: String]()

        dict[window] = "test"

        #expect(dict[window] == "test")
    }

    // MARK: - Computed Property Tests

    @Test("Only the Window Server's own windows are window server windows")
    func isWindowServerWindow() {
        let windowServerWindow = createWindowInfo(ownerName: "Window Server")
        let regularWindow = createWindowInfo(ownerName: "SomeApp")

        #expect(windowServerWindow.isWindowServerWindow)
        #expect(!regularWindow.isWindowServerWindow)
    }

    @Test("A nil owner name is not a window server window")
    func isWindowServerWindowWithNilOwnerName() {
        let window = createWindowInfo(ownerName: nil)

        #expect(!window.isWindowServerWindow)
    }

    @Test("A Window Server window is menu related")
    func isMenuRelatedForWindowServer() {
        let window = createWindowInfo(ownerName: "Window Server")

        #expect(window.isMenuRelated)
    }

    @Test("A main menu level window is menu related")
    func isMenuRelatedForMainMenuLevel() {
        // kCGMainMenuWindowLevel is typically 24
        let window = createWindowInfo(layer: Int(CGWindowLevelForKey(.mainMenuWindow)), ownerName: "SomeApp")

        #expect(window.isMenuRelated)
    }

    @Test("A status level window is menu related")
    func isMenuRelatedForStatusWindowLevel() {
        let window = createWindowInfo(layer: Int(CGWindowLevelForKey(.statusWindow)), ownerName: "SomeApp")

        #expect(window.isMenuRelated)
    }

    @Test("A pop-up menu level window is menu related")
    func isMenuRelatedForPopUpMenuLevel() {
        let window = createWindowInfo(layer: Int(CGWindowLevelForKey(.popUpMenuWindow)), ownerName: "SomeApp")

        #expect(window.isMenuRelated)
    }

    @Test("A normal level window is not menu related")
    func isNotMenuRelatedForRegularWindow() {
        // Normal window level is 0
        let window = createWindowInfo(layer: 0, ownerName: "SomeApp")

        #expect(!window.isMenuRelated)
    }
}
