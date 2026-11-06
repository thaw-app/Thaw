//
//  LauncherURIQueryHandlingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

extension SettingsURIResponseSuites {
    /// The read-only launcher operations: what they answer, to whom, and when they stay silent.
    @MainActor
    @Suite("Launcher URI queries")
    struct LauncherURIQueryHandlingTests {
        private let callback = "callback=floe://thaw-response"

        @Test("list-items sends the actionable items to the callback")
        func listItemsAnswersTheCallback() async throws {
            let fake = FakeLauncherEnvironment()
            fake.items = [
                .init(id: "com.example.app:Item", name: "Example", section: "hidden", bundleId: "com.example.app"),
                .init(id: "com.example.other:Item", name: "Other", section: "visible", bundleId: nil),
            ]
            let capture = try await fake.send("thaw://list-items?\(callback)&requestId=r1")

            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "success")
            #expect(response["operation"] as? String == "list-items")
            #expect(response["requestId"] as? String == "r1")
            let data = try #require(response["data"] as? [String: Any])
            let items = try #require(data["items"] as? [[String: Any]])
            #expect(items.map { $0["id"] as? String } == ["com.example.app:Item", "com.example.other:Item"])
            #expect(items.map { $0["section"] as? String } == ["hidden", "visible"])
            #expect(items[0]["bundleId"] as? String == "com.example.app")
            #expect(items[1]["bundleId"] == nil)
            #expect(capture.broadcasts.isEmpty)
        }

        @Test("The callback keeps its own query and gains the response as data")
        func callbackKeepsItsQuery() async throws {
            let fake = FakeLauncherEnvironment()
            let capture = try await fake.send("thaw://list-items?callback=floe://thaw-response?token%3Dabc")

            let url = try #require(capture.openedURLs.first)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.scheme == "floe")
            #expect(components.host == "thaw-response")
            #expect(components.queryItems?.first { $0.name == "token" }?.value == "abc")
            #expect(try capture.callbackResponse()["status"] as? String == "success")
        }

        @Test("Without Accessibility list-items says so instead of listing nothing")
        func listItemsReportsMissingPermission() async throws {
            let fake = FakeLauncherEnvironment()
            fake.hasPermission = false
            fake.items = [.init(id: "com.example.app:Item", name: "Example", section: "visible", bundleId: nil)]
            let capture = try await fake.send("thaw://list-items?\(callback)")

            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "error")
            #expect(response["error"] as? String == LauncherURIResponse.permissionMissing)
            #expect(response["data"] == nil)
            #expect(fake.itemReads == 0, "An unreadable bar must not be presented as an empty one")
        }

        @Test("A query with nowhere to answer does nothing", arguments: [
            LauncherURIOperation.listItems, .listProfiles, .getAppearance,
        ])
        func queryWithoutResponseMechanismIsDropped(operation: LauncherURIOperation) async throws {
            let fake = FakeLauncherEnvironment()
            let capture = try await fake.send("thaw://\(operation.rawValue)")

            #expect(capture.openedURLs.isEmpty)
            #expect(capture.broadcasts.isEmpty)
            #expect(fake.itemReads + fake.profileReads + fake.appearanceReads == 0)
        }

        @Test("A broadcast carries an acknowledgement, never the data", arguments: [
            LauncherURIOperation.listItems, .listProfiles, .getAppearance,
        ])
        func broadcastGetsOnlyAnAcknowledgement(operation: LauncherURIOperation) async throws {
            let fake = FakeLauncherEnvironment()
            fake.items = [.init(id: "com.example.app:Item", name: "Example", section: "visible", bundleId: nil)]
            fake.addProfile(named: "Work", active: true)
            let capture = try await fake.send("thaw://\(operation.rawValue)?broadcast=true&requestId=r2")

            #expect(capture.openedURLs.isEmpty)
            #expect(capture.broadcasts.count == 1)
            let response = try capture.broadcastResponse()
            #expect(response["status"] as? String == "ack")
            #expect(response["operation"] as? String == operation.rawValue)
            #expect(response["requestId"] as? String == "r2")
            #expect(response["data"] == nil, "Any process can hear a broadcast")
        }

        @Test("A callback is answered in full even when a broadcast was also requested")
        func callbackTakesPrecedenceOverBroadcast() async throws {
            let fake = FakeLauncherEnvironment()
            fake.addProfile(named: "Work")
            let capture = try await fake.send("thaw://list-profiles?\(callback)&broadcast=true")

            #expect(capture.broadcasts.isEmpty)
            #expect(try capture.callbackResponse()["status"] as? String == "success")
        }

        @Test("list-profiles names every saved profile and marks the active one")
        func listProfilesMarksTheActiveProfile() async throws {
            let fake = FakeLauncherEnvironment()
            let work = fake.addProfile(named: "Work")
            let home = fake.addProfile(named: "Home", active: true)
            let capture = try await fake.send("thaw://list-profiles?\(callback)")

            let response = try capture.callbackResponse()
            #expect(response["operation"] as? String == "list-profiles")
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["activeProfileId"] as? String == home.uuidString)
            let profiles = try #require(data["profiles"] as? [[String: Any]])
            #expect(profiles.map { $0["id"] as? String } == [work.uuidString, home.uuidString])
            #expect(profiles.map { $0["name"] as? String } == ["Work", "Home"])
            #expect(profiles.map { $0["isActive"] as? Bool } == [false, true])
        }

        @Test("get-appearance sends the shared appearance as it is encoded for partners")
        func getAppearanceSendsTheSharedAppearance() async throws {
            let fake = FakeLauncherEnvironment()
            let capture = try await fake.send("thaw://get-appearance?\(callback)")

            let response = try capture.callbackResponse()
            #expect(response["operation"] as? String == "get-appearance")
            #expect(response["status"] as? String == "success")
            let data = try #require(response["data"] as? [String: Any])
            let encoded = try JSONEncoder().encode(fake.appearance)
            let expected = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(NSDictionary(dictionary: data) == NSDictionary(dictionary: expected))
            #expect(data["colorScheme"] as? String == "dark")
            #expect(fake.itemReads + fake.profileReads == 0)
        }

        @Test("A request without an identifier of its own is given one to answer under")
        func missingRequestIdentifierIsGenerated() async throws {
            let fake = FakeLauncherEnvironment()
            let capture = try await fake.send("thaw://list-profiles?\(callback)")

            let requestId = try #require(try capture.callbackResponse()["requestId"] as? String)
            #expect(UUID(uuidString: requestId) != nil)
        }

        @Test("A callback with a blocked scheme is never opened", arguments: [
            "file:///tmp/out", "javascript:alert(1)", "x-apple-reminder://x",
        ])
        func blockedCallbackSchemeIsNotOpened(target: String) async throws {
            let fake = FakeLauncherEnvironment()
            let encoded = try #require(target.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
            let capture = try await fake.send("thaw://list-profiles?callback=\(encoded)")

            #expect(capture.openedURLs.isEmpty)
            #expect(capture.broadcasts.isEmpty)
        }
    }
}
