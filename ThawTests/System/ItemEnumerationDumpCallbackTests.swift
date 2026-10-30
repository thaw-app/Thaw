//
//  ItemEnumerationDumpCallbackTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Where thaw://dump-items may send its report path and summary.
@MainActor
@Suite("Item dump callback")
struct ItemEnumerationDumpCallbackTests {
    private let sender = "com.stonerl.Thaw.ctl"

    private let senderApp = URL(fileURLWithPath: "/Applications/ThawCtl.app")

    /// handler stands in for the app CallbackRecipient finds: the sender's own app, or another one.
    private func deliverable(_ callback: String?, handler: String? = "com.stonerl.Thaw.ctl") -> URLComponents? {
        ItemEnumerationDump.deliverableCallback(callback) { _ in
            handler?.caseInsensitiveCompare(sender) == .orderedSame ? senderApp : nil
        }?.components
    }

    @Test("A callback the approved sender handles is accepted")
    func senderOwnSchemeIsAccepted() throws {
        let components = try #require(deliverable("thawctl://response?source=gui"))
        #expect(components.scheme == "thawctl")
        #expect(deliverable("thawctl://response", handler: "COM.STONERL.THAW.CTL") != nil)
    }

    @Test("A callback another app handles is refused")
    func otherHandlerIsRefused() {
        #expect(deliverable("thawctl://response", handler: "com.example.other") == nil)
        #expect(deliverable("thawctl://response", handler: nil) == nil)
    }

    @Test("Web, messaging and code schemes are refused even when the sender handles them", arguments: [
        "https://example.com/collect", "http://example.com/collect", "HTTPS://example.com", "ftp://example.com/x",
        "wss://example.com", "mailto:someone@example.com", "sms:123", "file:///tmp/x", "javascript:alert(1)",
        "data:text/plain,x", "x-apple-helpviewer://x",
    ])
    func networkSchemesAreRefused(callback: String) {
        #expect(deliverable(callback) == nil)
    }

    @Test("A missing, empty or scheme-less callback is refused", arguments: [nil, "", "response", "://nothing"] as [String?])
    func malformedCallbackIsRefused(callback: String?) {
        #expect(deliverable(callback) == nil)
    }

    @Test("The callback carries only the file path and a per-app summary")
    func callbackCarriesPathAndSummary() throws {
        let item = ItemEnumerationDump.DumpedItem(
            index: 0, occurrence: 0, role: "AXMenuBarItem", title: "Clock", identifier: nil, description: nil,
            help: "secret help text", valueDescription: nil, stringValue: nil,
            frameX: 0, frameY: 0, frameWidth: 20, frameHeight: 24, childCount: 0, innerAttributes: nil
        )
        let unkeyed = ItemEnumerationDump.DumpedItem(
            index: 1, occurrence: 0, role: nil, title: nil, identifier: nil, description: nil,
            help: nil, valueDescription: nil, stringValue: nil,
            frameX: 0, frameY: 0, frameWidth: 20, frameHeight: 24, childCount: 0, innerAttributes: nil
        )
        let apps = [ItemEnumerationDump.DumpedApp(bundleIdentifier: "com.example.app", processIdentifier: 42, items: [item, unkeyed])]
        let callback = try #require(deliverable("thawctl://response?source=gui"))
        let fileURL = URL(fileURLWithPath: "/tmp/item-dump-1.json")

        let url = try #require(ItemEnumerationDump.callbackURL(callback, fileURL: fileURL, apps: apps))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.scheme == "thawctl")
        #expect(query["source"] == "gui")
        #expect(query["type"] == "item-dump")
        #expect(query["file"] == fileURL.path)
        let data = try #require(query["data"].flatMap(\.self)?.data(using: .utf8))
        let summary = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(summary.count == 1)
        #expect(summary.first?["bundle"] as? String == "com.example.app")
        #expect(summary.first?["count"] as? Int == 2)
        #expect(summary.first?["keyed"] as? Int == 1)
        #expect(!url.absoluteString.contains("secret"), "Item attributes stay in the file")
    }
}
