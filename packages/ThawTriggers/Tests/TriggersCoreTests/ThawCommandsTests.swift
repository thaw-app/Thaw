//
//  ThawCommandsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
import TriggersCore

@Suite("Thaw commands")
struct ThawCommandsTests {
    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test("Holding an item asks reveal-item to keep it shown")
    func holdURL() {
        let url = ThawCommands.hold(itemID: "com.example.app:Item:1")
        #expect(url.scheme == "thaw")
        #expect(url.host == "reveal-item")
        #expect(query(url) == ["item-id": "com.example.app:Item:1", "hold": "true"])
    }

    @Test("Releasing an item uses release-item with the same id")
    func releaseURL() {
        let url = ThawCommands.release(itemID: "com.example.app:Item")
        #expect(url.host == "release-item")
        #expect(query(url) == ["item-id": "com.example.app:Item"])
    }

    @Test("Listing items asks Thaw to answer on the module's own scheme")
    func listItemsURL() {
        let url = ThawCommands.listItems(callbackScheme: "com.stonerl.thaw.module.triggers", requestID: "7")
        #expect(url.host == "list-items")
        #expect(query(url) == ["callback": "com.stonerl.thaw.module.triggers://list-items", "requestId": "7"])
    }
}

@Suite("Thaw item list")
struct ThawItemListTests {
    private func callback(_ json: String) -> URL {
        var components = URLComponents(string: "com.stonerl.thaw.module.triggers://list-items")!
        components.queryItems = [URLQueryItem(name: "data", value: json)]
        return components.url!
    }

    @Test("A successful reply gives the items in the order Thaw sent them")
    func readsItems() throws {
        let url = callback(#"{"operation":"list-items","requestId":"7","status":"success","data":{"version":1,"items":[{"id":"com.example.app:Item","name":"Example","section":"hidden","bundleId":"com.example.app"},{"id":"other:Item","name":"Other","section":"visible"}]}}"#)
        let reply = try #require(ThawItemList.reply(fromCallback: url))
        #expect(reply.requestID == "7")
        #expect(reply.items == .success([
            ThawItem(id: "com.example.app:Item", name: "Example", section: "hidden", bundleId: "com.example.app"),
            ThawItem(id: "other:Item", name: "Other", section: "visible", bundleId: nil),
        ]))
    }

    @Test("An error reply keeps Thaw's explanation")
    func readsErrors() throws {
        let url = callback(#"{"operation":"list-items","requestId":"8","status":"error","error":"permissionMissing","details":"Accessibility permission is not granted"}"#)
        let reply = try #require(ThawItemList.reply(fromCallback: url))
        #expect(reply.items == .failure(.thaw(code: "permissionMissing", details: "Accessibility permission is not granted")))
    }

    @Test("Anything that isn't a list-items reply is ignored")
    func ignoresOtherURLs() {
        #expect(ThawItemList.reply(fromCallback: URL(string: "com.stonerl.thaw.module.triggers://other?data=%7B%7D")!) == nil)
        #expect(ThawItemList.reply(fromCallback: callback("not json")) == nil)
    }
}
