//
//  ThawItemSourceTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import TriggersCore

@MainActor
@Suite("Thaw item source")
struct ThawItemSourceTests {
    private let item = ThawItem(id: "com.example:Item-0", name: "Example", section: "hidden", bundleId: "com.example")

    /// A source whose requests are recorded, so a test can answer them.
    private func makeSource() -> (ThawItemSource, () -> String?) {
        let source = ThawItemSource()
        var lastRequest: String?
        source.request = { lastRequest = $0 }
        return (source, { lastRequest })
    }

    @Test("A reply to the latest request fills the list")
    func acceptsTheLatestReply() throws {
        let (source, lastRequest) = makeSource()
        source.refresh()
        let requestID = try #require(lastRequest())

        source.receive(ThawItemList.Reply(requestID: requestID, items: .success([item])))

        #expect(source.items == [item])
        #expect(source.problem == nil)
    }

    @Test("A reply to an older or unknown request is ignored")
    func ignoresStaleReplies() throws {
        let (source, lastRequest) = makeSource()
        source.refresh()
        let older = try #require(lastRequest())
        source.refresh()

        source.receive(ThawItemList.Reply(requestID: older, items: .success([item])))
        source.receive(ThawItemList.Reply(requestID: nil, items: .success([item])))

        #expect(source.items.isEmpty)
    }

    @Test("Thaw's error keeps the last list and says what went wrong")
    func reportsThawErrors() throws {
        let (source, lastRequest) = makeSource()
        source.refresh()
        try source.receive(ThawItemList.Reply(requestID: #require(lastRequest()), items: .success([item])))
        source.refresh()

        try source.receive(ThawItemList.Reply(requestID: #require(lastRequest()), items: .failure(.thaw(code: "unavailable", details: "Thaw isn't ready"))))

        #expect(source.items == [item])
        #expect(source.problem == "Thaw isn't ready")
    }
}
