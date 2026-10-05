//
//  SettingsURIDeliveryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

extension SettingsURIResponseSuites {
    /// The two ways a thaw:// response leaves the app, and what each refuses to send.
    @MainActor
    @Suite("Settings URI response delivery")
    struct SettingsURIDeliveryTests {
        private let response: [String: Any] = ["requestId": "r1", "status": "success", "value": 3]

        @Test("A callback is opened with the response appended as JSON")
        func callbackCarriesTheResponse() async throws {
            let capture = URIDeliveryCapture()
            let sent = await capture.run {
                SettingsURIHandler.sendCallbackResponse(response: response, callback: "raycast://extensions/thaw?source=test")
            }

            #expect(sent)
            let url = try #require(capture.openedURLs.first)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.scheme == "raycast")
            #expect(components.queryItems?.map(\.name) == ["source", "data"])
            let decoded = try capture.callbackResponse()
            #expect(decoded["requestId"] as? String == "r1")
            #expect(decoded["value"] as? Int == 3)
        }

        @Test("A callback that cannot be opened is reported as not sent")
        func unopenedCallbackIsAFailure() async {
            let capture = URIDeliveryCapture()
            capture.openSucceeds = false
            let sent = await capture.run {
                SettingsURIHandler.sendCallbackResponse(response: response, callback: "floe://thaw-response")
            }

            #expect(!sent)
            #expect(capture.openedURLs.count == 1)
        }

        @Test("Callbacks that could run code or read files are refused unopened", arguments: [
            "file:///etc/hosts",
            "FILE:///etc/hosts",
            "javascript:alert(1)",
            "data:text/html,hi",
            "about:blank",
            "blob:abc",
            "x-apple-systempreferences:com.apple.preference.security",
            "no-scheme-here",
            "",
        ])
        func unsafeCallbackIsRefused(callback: String) async {
            let capture = URIDeliveryCapture()
            let sent = await capture.run {
                SettingsURIHandler.sendCallbackResponse(response: response, callback: callback)
            }

            #expect(!sent)
            #expect(capture.openedURLs.isEmpty)
        }

        @Test("A broadcast posts the response once, as key-sorted JSON")
        func broadcastPostsSortedJSON() async throws {
            let capture = URIDeliveryCapture()
            let sent = await capture.run {
                SettingsURIHandler.sendBroadcastResponse(response: response)
            }

            #expect(sent)
            #expect(capture.broadcasts == [#"{"requestId":"r1","status":"success","value":3}"#])
            #expect(capture.openedURLs.isEmpty)
        }
    }
}
