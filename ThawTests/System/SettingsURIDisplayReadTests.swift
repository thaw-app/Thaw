//
//  SettingsURIDisplayReadTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel
import Testing
@testable import Thaw

extension SettingsURIResponseSuites {
    /// Reads of a connected display, of a stored value the key does not name, and of the
    /// app names and icons the approval prompt shows. Answers are captured, never sent.
    @MainActor
    @Suite("Settings URI display and app reads", .scratchDefaults)
    struct SettingsURIDisplayReadTests {
        private func get(_ key: String, display: String? = nil) async throws -> [String: Any] {
            let capture = URIDeliveryCapture()
            let sent = await capture.run {
                SettingsURIHandler.handleGet(
                    key: key,
                    displayUUID: display,
                    callback: "floe://thaw-response",
                    broadcast: false,
                    requestId: "req",
                    recipient: nil
                )
            }
            #expect(sent)
            return try capture.callbackResponse()
        }

        @Test("Reading a connected display describes that display")
        func connectedDisplay() async throws {
            let mainID = CGMainDisplayID()
            let uuid = try #require(Bridging.getDisplayUUIDString(for: mainID))
            let screen = try #require(NSScreen.screen(for: mainID))
            let response = try await get("display", display: uuid)
            #expect(response["status"] as? String == "success")
            #expect(response["requestId"] as? String == "req")
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["uuid"] as? String == uuid)
            #expect(data["name"] as? String == screen.localizedName)
            #expect(data["isConnected"] as? Bool == true)
        }

        @Test("A stored strategy number with no name is reported by number alone")
        func unnamedStrategyNumber() async throws {
            Defaults.set(99, forKey: .rehideStrategy)
            let response = try await get("rehideStrategy")
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["rawValue"] as? Int == 99)
            #expect(data["type"] as? String == "enum")
            #expect(data["value"] == nil)
        }

        @Test("A callback that is not a URL is refused unopened")
        func malformedCallback() async {
            let capture = URIDeliveryCapture()
            let sent = await capture.run {
                SettingsURIHandler.sendCallbackResponse(response: ["status": "success"], callback: "floe://[", recipient: nil)
            }
            #expect(!sent)
            #expect(capture.openedURLs.isEmpty)
        }

        @Test("A running app is named by its running name, and has an icon")
        func runningAppNameAndIcon() throws {
            let finder = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first)
            #expect(SettingsURIHandler.getAppName(for: "com.apple.finder") == finder.localizedName)
            #expect(SettingsURIHandler.getAppIcon(for: "com.apple.finder") != nil)
        }

        @Test("An installed app that is not running is named from its bundle")
        func installedAppName() throws {
            let candidates = ["com.apple.Chess", "com.apple.Stickies", "com.apple.TextEdit", "com.apple.Dictionary"]
            let bundleID = try #require(candidates.first {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
                    && NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }, "The test needs one of these apps installed and not running")
            let url = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID))
            let expected = Bundle(url: url)?.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            #expect(expected != nil)
            #expect(SettingsURIHandler.getAppName(for: bundleID) == expected)
        }

        @Test("An app that is neither running nor installed has no name and no icon")
        func unknownAppHasNoNameOrIcon() {
            #expect(SettingsURIHandler.getAppName(for: "com.example.thaw.not-installed") == nil)
            #expect(SettingsURIHandler.getAppIcon(for: "com.example.thaw.not-installed") == nil)
        }
    }
}
