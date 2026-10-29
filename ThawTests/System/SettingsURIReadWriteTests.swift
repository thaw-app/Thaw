//
//  SettingsURIReadWriteTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// What thaw://set, thaw://toggle and thaw://get do with a key, against a scratch settings store.
/// Changes are announced on a private center, and per-display writes are only tried with
/// values that are refused before anything is announced.
@MainActor
@Suite("Settings URI reads and writes", .serialized, .scratchDefaults)
struct SettingsURIReadWriteTests {
    /// Runs body with announcements going to a private center, returning what was announced.
    private func announcements(_ body: () -> Void) -> [[AnyHashable: Any]] {
        var received: [[AnyHashable: Any]] = []
        withPrivateSettingsChangeCenter {
            let center = SettingsURIHandler.settingsChangeNotificationCenter
            let token = center.addObserver(forName: .settingsDidChangeViaURI, object: nil, queue: nil) { note in
                received.append(note.userInfo ?? [:])
            }
            body()
            center.removeObserver(token)
        }
        return received
    }

    private func get(_ key: String?, display: String? = nil) async throws -> [String: Any] {
        let capture = URIDeliveryCapture()
        let sent = await capture.run {
            SettingsURIHandler.handleGet(key: key, displayUUID: display, callback: "floe://thaw-response", broadcast: false, requestId: "req", recipient: nil)
        }
        #expect(sent)
        return try capture.callbackResponse()
    }

    /// A display that is not connected but has a saved configuration.
    private func persistDisconnectedDisplay() throws -> String {
        let uuid = UUID().uuidString
        let data = try JSONEncoder().encode([uuid: DisplayThawBarConfiguration.defaultConfiguration])
        Defaults.set(data, forKey: .displayThawBarConfigurations)
        return uuid
    }

    // MARK: Parsing

    @Test("Booleans accept the usual spellings in any case and nothing else", arguments: [
        ("true", true), ("YES", true), ("1", true), ("False", false), ("no", false), ("0", false),
    ])
    func parseBool(text: String, expected: Bool) {
        #expect(SettingsURIHandler.parseBool(text) == expected)
    }

    @Test("Unrecognized booleans and numbers are refused")
    func parseRefusals() {
        #expect(SettingsURIHandler.parseBool("maybe") == nil)
        #expect(SettingsURIHandler.parseBool("") == nil)
        #expect(SettingsURIHandler.parseDouble("2.5") == 2.5)
        #expect(SettingsURIHandler.parseDouble("fast") == nil)
    }

    // MARK: Writes

    @Test("Setting a boolean saves it and announces the new value")
    func setBoolean() {
        let posted = announcements {
            #expect(SettingsURIHandler.handleSet(key: "showOnHover", value: "yes", sender: "com.example.app"))
        }
        #expect(Defaults.bool(forKey: .showOnHover))
        #expect(posted.count == 1)
        #expect(posted.first?["key"] as? String == "showOnHover")
        #expect(posted.first?["value"] as? Bool == true)
    }

    @Test("A boolean that does not parse changes nothing")
    func setBadBoolean() {
        Defaults.set(false, forKey: .showOnHover)
        let posted = announcements {
            #expect(!SettingsURIHandler.handleSet(key: "showOnHover", value: "perhaps", sender: nil))
        }
        #expect(!Defaults.bool(forKey: .showOnHover))
        #expect(posted.isEmpty)
    }

    @Test("Numbers are clamped into the key's range")
    func setDoubleClamps() {
        let posted = announcements {
            #expect(SettingsURIHandler.handleSet(key: "rehideInterval", value: "9999", sender: nil))
            #expect(SettingsURIHandler.handleSet(key: "tempShowInterval", value: "-4", sender: nil))
        }
        #expect(Defaults.double(forKey: .rehideInterval) == 300)
        #expect(Defaults.double(forKey: .tempShowInterval) == 0)
        #expect(posted.compactMap { $0["doubleValue"] as? Double } == [300, 0])
    }

    @Test("Numbers that are not numbers or not finite are refused")
    func setBadDouble() {
        let posted = announcements {
            #expect(!SettingsURIHandler.handleSet(key: "tooltipDelay", value: "soon", sender: nil))
            #expect(!SettingsURIHandler.handleSet(key: "tooltipDelay", value: "nan", sender: nil))
            #expect(!SettingsURIHandler.handleSet(key: "tooltipDelay", value: "inf", sender: nil))
        }
        #expect(posted.isEmpty)
    }

    @Test("The rehide strategy is set by name and announced by number")
    func setEnumeration() {
        let posted = announcements {
            #expect(SettingsURIHandler.handleSet(key: "rehideStrategy", value: "timed", sender: nil))
            #expect(!SettingsURIHandler.handleSet(key: "rehideStrategy", value: "sometimes", sender: nil))
        }
        #expect(Defaults.integer(forKey: .rehideStrategy) == RehideStrategy.timed.rawValue)
        #expect(posted.count == 1)
        #expect(posted.first?["rawEnumValue"] as? Int == RehideStrategy.timed.rawValue)
    }

    @Test("Unknown and read-only keys cannot be written")
    func setRefusedKeys() {
        let posted = announcements {
            #expect(!SettingsURIHandler.handleSet(key: "noSuchKey", value: "true", sender: nil))
            #expect(!SettingsURIHandler.handleSet(key: "enableExperimentalSystemItemHiding", value: "true", sender: nil))
            #expect(!SettingsURIHandler.handleToggle(key: "noSuchKey", sender: nil))
            #expect(!SettingsURIHandler.handleToggle(key: "rehideInterval", sender: nil))
        }
        #expect(posted.isEmpty)
    }

    @Test("Toggling flips the saved value each time")
    func toggle() {
        Defaults.set(false, forKey: .enableSwapBar)
        let posted = announcements {
            #expect(SettingsURIHandler.handleToggle(key: "enableSwapBar", sender: "com.example.app"))
            #expect(Defaults.bool(forKey: .enableSwapBar))
            #expect(SettingsURIHandler.handleToggle(key: "enableSwapBar", sender: "com.example.app"))
        }
        #expect(!Defaults.bool(forKey: .enableSwapBar))
        #expect(posted.compactMap { $0["value"] as? Bool } == [true, false])
    }

    @Test("Per-display writes with values that do not parse are refused", arguments: [
        ("useThawBar", "perhaps"),
        ("alwaysShowHiddenItems", "perhaps"),
        ("thawBarLocation", "sideways"),
        ("thawBarLayout", "spiral"),
        ("gridColumns", "many"),
    ])
    func perDisplayRefusals(key: String, value: String) {
        #expect(!SettingsURIHandler.handleSet(key: key, value: value, sender: nil))
    }

    @Test("Per-display writes need a well-formed, known display")
    func perDisplayScope() {
        #expect(!SettingsURIHandler.handleSet(key: "useThawBar", value: "true", sender: nil, displayUUID: "not-a-uuid"))
        #expect(!SettingsURIHandler.handleSet(key: "useThawBar", value: "true", sender: nil, displayUUID: UUID().uuidString))
        #expect(!SettingsURIHandler.handleToggle(key: "useThawBar", sender: nil, displayUUID: UUID().uuidString))
        #expect(!SettingsURIHandler.handleToggle(key: "thawBarLocation", sender: nil))
    }

    @Test("A per-display scope names itself for the notification and the log")
    func perDisplayScopeNames() {
        typealias Scope = SettingsURIHandler.PerDisplayScope
        #expect(Scope.activeDisplay.rawValue == "active")
        #expect(Scope.allEnabledDisplays.rawValue == "allEnabled")
        #expect(Scope.allNonThawBarDisplays.rawValue == "allNonThawBar")
        #expect(Scope.specificDisplay(uuid: "X").rawValue == "specific:X")
        #expect(Scope.specificDisplay(uuid: "X").specificUUID == "X")
        #expect(Scope.activeDisplay.specificUUID == nil)
        for scope in [Scope.activeDisplay, .allEnabledDisplays, .allNonThawBarDisplays, .specificDisplay(uuid: "X")] {
            #expect(!scope.logDescription.isEmpty)
        }
    }

    // MARK: Reads

    @Test("A read needs somewhere to send the answer")
    func getNeedsAResponseRoute() {
        #expect(!SettingsURIHandler.handleGet(key: "version", displayUUID: nil, callback: nil, broadcast: false, requestId: nil, recipient: nil))
    }

    @Test("A broadcast read only acknowledges, so other listeners learn no settings")
    func broadcastOnlyAcknowledges() async throws {
        let capture = URIDeliveryCapture()
        let sent = await capture.run {
            SettingsURIHandler.handleGet(key: "all", displayUUID: nil, callback: nil, broadcast: true, requestId: "b1", recipient: nil)
        }
        #expect(sent)
        let response = try capture.broadcastResponse()
        #expect(response["status"] as? String == "ack")
        #expect(response["requestId"] as? String == "b1")
        #expect(response["data"] == nil)
    }

    @Test("Reading a boolean, a number and the strategy reports value and type")
    func getGlobalValues() async throws {
        Defaults.set(true, forKey: .showOnScroll)
        Defaults.set(12.0, forKey: .rehideInterval)
        Defaults.set(RehideStrategy.focusedApp.rawValue, forKey: .rehideStrategy)

        let bool = try #require(try await get("showOnScroll")["data"] as? [String: Any])
        #expect(bool["value"] as? Bool == true)
        #expect(bool["type"] as? String == "boolean")

        let number = try #require(try await get("rehideInterval")["data"] as? [String: Any])
        #expect(number["value"] as? Double == 12)
        #expect(number["type"] as? String == "double")

        let strategy = try #require(try await get("rehideStrategy")["data"] as? [String: Any])
        #expect(strategy["rawValue"] as? Int == RehideStrategy.focusedApp.rawValue)
        #expect(strategy["type"] as? String == "enum")
    }

    @Test("Reading with no key or an unknown key answers with an error")
    func getErrors() async throws {
        let missing = try await get(nil)
        #expect(missing["status"] as? String == "error")
        let unknown = try await get("noSuchKey")
        #expect(unknown["status"] as? String == "error")
        #expect(unknown["requestId"] as? String == "req")
        let noDisplay = try await get("display")
        #expect(noDisplay["status"] as? String == "error")
        let unknownDisplay = try await get("display", display: UUID().uuidString)
        #expect(unknownDisplay["error"] as? String == "Display not found")
    }

    @Test("The version read reports the bundle's version")
    func getVersion() async throws {
        let response = try await get("version")
        let data = try #require(response["data"] as? [String: Any])
        #expect(data["value"] as? String == Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        #expect(data["type"] as? String == "string")
    }

    @Test("Reading everything lists every global key and the displays")
    func getAll() async throws {
        let response = try await get("all")
        #expect(response["status"] as? String == "success")
        let data = try #require(response["data"] as? [String: Any])
        let global = try #require(data["global"] as? [String: Any])
        #expect(Set(global.keys) == Set(SettingsURIHandler.keyTable.keys))
        #expect(data["displays"] is [String: Any])
        #expect(data["appVersion"] is [String: Any])
    }

    @Test("Reading the displays lists each connected one with its configuration")
    func getDisplays() async throws {
        let response = try await get("displays")
        let data = try #require(response["data"] as? [String: Any])
        let displays = try #require(data["displays"] as? [[String: Any]])
        for display in displays {
            #expect(display["uuid"] is String)
            #expect(display["gridColumns"] is Int)
        }
    }

    @Test("A saved display that is not connected still answers, marked disconnected")
    func getDisconnectedDisplay() async throws {
        let uuid = try persistDisconnectedDisplay()
        let response = try await get("display", display: uuid)
        let data = try #require(response["data"] as? [String: Any])
        #expect(data["isConnected"] as? Bool == false)
        #expect(data["uuid"] as? String == uuid)
        let config = DisplayThawBarConfiguration.defaultConfiguration
        #expect(data["useThawBar"] as? Bool == config.useThawBar)
        #expect(data["gridColumns"] as? Int == config.gridColumns)
    }

    @Test("Per-display keys read the saved configuration of the named display", arguments: [
        "useThawBar", "thawBarLocation", "alwaysShowHiddenItems", "thawBarLayout", "gridColumns",
    ])
    func getPerDisplayKey(key: String) async throws {
        let uuid = try persistDisconnectedDisplay()
        let response = try await get(key, display: uuid)
        #expect(response["status"] as? String == "success")
        let data = try #require(response["data"] as? [String: Any])
        #expect(data["type"] is String)
        let unknown = try await get(key, display: UUID().uuidString)
        #expect(unknown["status"] as? String == "error")
        let active = try await get(key)
        #expect(active["status"] as? String == "success")
    }

    @Test("Per-display writes to a saved display pass the scope check before the value check")
    func perDisplayKnownDisplayStillValidatesValue() throws {
        let uuid = try persistDisconnectedDisplay()
        #expect(!SettingsURIHandler.handleSet(key: "gridColumns", value: "lots", sender: nil, displayUUID: uuid))
        #expect(!SettingsURIHandler.handleSet(key: "thawBarLayout", value: "spiral", sender: nil, displayUUID: uuid))
    }

    // MARK: Delivery

    @Test("Callbacks with a dangerous or missing scheme are never opened", arguments: [
        "file:///tmp/x", "javascript:alert(1)", "x-apple-helpviewer://x", "no-scheme", "",
    ])
    func refusedCallbacks(callback: String) async {
        let capture = URIDeliveryCapture()
        let sent = await capture.run {
            SettingsURIHandler.sendCallbackResponse(response: ["status": "success"], callback: callback, recipient: nil)
        }
        #expect(!sent)
        #expect(capture.openedURLs.isEmpty)
    }

    @Test("A callback the system cannot open reports failure")
    func callbackOpenFails() async {
        let capture = URIDeliveryCapture()
        capture.openSucceeds = false
        let sent = await capture.run {
            SettingsURIHandler.sendCallbackResponse(response: ["status": "success"], callback: "floe://x?keep=1", recipient: nil)
        }
        #expect(!sent)
        let query = capture.openedURLs.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        #expect(query?.contains { $0.name == "keep" } == true)
        #expect(query?.contains { $0.name == "data" } == true)
    }
}
