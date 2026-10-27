//
//  MoveItemURLHandlingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

extension SettingsURIResponseSuites {
    /// thaw://move-item and thaw://list-items as a client sees them, and the gate both pass.
    @MainActor
    @Suite("Move item URL handling", .serialized)
    struct MoveItemURLHandlingTests {
        private let callback = "callback=floe://thaw-response"

        @Test("A move is handed over once, and its success names the items, section and anchor")
        func moveReportsSuccess() async throws {
            let fake = FakeLauncherEnvironment()
            fake.moveOutcome = { command in
                .moved(LayoutBatchMovePlan(
                    itemIDs: command.itemIDs,
                    source: .hidden,
                    target: command.section,
                    previousTargetOrder: [],
                    targetOrder: command.itemIDs
                ))
            }
            let capture = try await fake.send(
                "thaw://move-item?item-id=com.example.a%3AItem-0&item-id=com.example.b%3AItem-0&section=visible&after-id=w&\(callback)&requestId=m1"
            )

            #expect(fake.moves.map(\.itemIDs) == [["com.example.a:Item-0", "com.example.b:Item-0"]])
            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "success")
            #expect(response["operation"] as? String == "move-item")
            #expect(response["requestId"] as? String == "m1")
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["version"] as? Int == 1)
            #expect(data["itemIds"] as? [String] == ["com.example.a:Item-0", "com.example.b:Item-0"])
            #expect(data["section"] as? String == "visible")
            #expect(data["afterId"] as? String == "w")
            #expect(data["outcome"] as? String == "moved")
        }

        @Test("A move that changes nothing succeeds as unchanged")
        func unchangedMoveSucceeds() async throws {
            let fake = FakeLauncherEnvironment()
            fake.moveOutcome = { command in
                .unchanged(LayoutBatchMovePlan(
                    itemIDs: command.itemIDs,
                    source: .visible,
                    target: .visible,
                    previousTargetOrder: ["a"],
                    targetOrder: ["a"]
                ))
            }
            let response = try await fake.send("thaw://move-item?item-id=a&section=visible&\(callback)").callbackResponse()

            #expect(response["status"] as? String == "success")
            #expect((response["data"] as? [String: Any])?["outcome"] as? String == "unchanged")
        }

        @Test("A refused move is an error with its code and reason")
        func refusedMoveReportsWhy() async throws {
            let fake = FakeLauncherEnvironment()
            fake.moveOutcome = { _ in .refused(.controlItem("thaw")) }
            let response = try await fake.send("thaw://move-item?item-id=thaw&section=hidden&\(callback)").callbackResponse()

            #expect(response["status"] as? String == "error")
            #expect(response["error"] as? String == "itemNotMovable")
            #expect((response["details"] as? String)?.contains("thaw") == true)
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["outcome"] as? String == "itemNotMovable")
            #expect(data["afterId"] == nil)
        }

        @Test("A malformed move is refused before it reaches the move path")
        func malformedMoveNeverMoves() async throws {
            let fake = FakeLauncherEnvironment()
            let response = try await fake.send("thaw://move-item?item-id=a&section=top&\(callback)").callbackResponse()

            #expect(fake.moves.isEmpty)
            #expect(response["error"] as? String == "invalidRequest")
            #expect((response["details"] as? String)?.contains("top") == true)
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["itemIds"] as? [String] == [])
        }

        @Test("A move runs without a response mechanism, and a broadcast only acknowledges it")
        func moveRunsWithoutResponse() async throws {
            let fake = FakeLauncherEnvironment()
            let silent = try await fake.send("thaw://move-item?item-id=a&section=hidden")
            let broadcast = try await fake.send("thaw://move-item?item-id=a&section=hidden&broadcast=true")

            #expect(fake.moves.count == 2)
            #expect(silent.openedURLs.isEmpty && silent.broadcasts.isEmpty)
            #expect(try broadcast.broadcastResponse()["status"] as? String == "ack")
        }

        @Test("list-items gives each item's identifier, name and section, the values move-item takes")
        func listItemsShape() async throws {
            let fake = FakeLauncherEnvironment()
            fake.items = [LauncherURIPayload.Item(id: "com.example.app:Item-0", name: "Example", section: "hidden", bundleId: nil)]
            let response = try await fake.send("thaw://list-items?\(callback)").callbackResponse()

            let data = try #require(response["data"] as? [String: Any])
            let items = try #require(data["items"] as? [[String: Any]])
            #expect(items.count == 1)
            #expect(items.first?["id"] as? String == "com.example.app:Item-0")
            #expect(items.first?["name"] as? String == "Example")
            #expect(items.first?["section"] as? String == "hidden")
            #expect(try LauncherURIRequest(url: #require(URL(string: "thaw://move-item?item-id=x&section=hidden")))?.operation == .moveItem)
        }

        @Test("The gate move-item passes refuses an unapproved or unknown sender and admits an approved one", .scratchDefaults)
        func gateRefusesUnapprovedSenders() {
            let bundleID = "com.example.thawtests.mover.\(UUID().uuidString)"
            let sender = SettingsURISender(bundleIdentifier: bundleID, teamIdentifier: "TEAMID1234", codeHash: nil)
            #expect(!SettingsURIHandler.isWhitelisted(sender: sender, builtInTrust: { _ in false }))
            #expect(!SettingsURIHandler.isWhitelisted(sender: nil, builtInTrust: { _ in false }))
            SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")
            #expect(SettingsURIHandler.isWhitelisted(sender: sender, builtInTrust: { _ in false }))
            SettingsURIHandler.removeFromWhitelist(bundleId: bundleID)
            #expect(!SettingsURIHandler.isWhitelisted(sender: sender, builtInTrust: { _ in false }))
        }

        @Test("An approved sender signed by a different team than it was approved with is refused", .scratchDefaults)
        func gateRefusesASignatureMismatch() {
            let bundleID = "com.example.thawtests.mover.\(UUID().uuidString)"
            SettingsURIHandler.addToWhitelist(bundleId: bundleID, teamIdentifier: "TEAMID1234")
            let impostor = SettingsURISender(bundleIdentifier: bundleID, teamIdentifier: "OTHERTEAM1", codeHash: nil)
            #expect(!SettingsURIHandler.isWhitelisted(sender: impostor, builtInTrust: { _ in false }))
        }
    }
}
