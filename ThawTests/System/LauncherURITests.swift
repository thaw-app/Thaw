//
//  LauncherURITests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The parts of the launcher operations that need no live menu bar: URL parsing,
/// wire payloads, and the response each outcome becomes.
@Suite("Launcher URI")
struct LauncherURITests {
    private func request(_ string: String) throws -> LauncherURIRequest? {
        try LauncherURIRequest(url: #require(URL(string: string)))
    }

    /// The response as a receiver sees it: through the same serializer the
    /// callback path uses, then parsed back.
    private func wire(_ response: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: response, options: .sortedKeys)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Parsing

    @Test("Each operation is recognised by its host", arguments: LauncherURIOperation.allCases)
    func hostsParse(operation: LauncherURIOperation) throws {
        let parsed = try #require(try request("thaw://\(operation.rawValue)"))
        #expect(parsed.operation == operation)
        #expect(parsed.identifier == nil)
        #expect(parsed.callback == nil)
        #expect(!parsed.broadcast)
        #expect(parsed.requestId == nil)
        #expect(!parsed.hasResponseMechanism)
    }

    @Test("A host that is not a launcher operation is not parsed")
    func otherHostsAreRejected() throws {
        #expect(try request("thaw://get?key=all") == nil)
        #expect(try request("thaw://activate") == nil)
        #expect(try request("thaw:list-items") == nil)
    }

    @Test("The host is matched case-insensitively, as the dispatch does")
    func hostCaseIsIgnored() throws {
        #expect(try request("thaw://List-Items")?.operation == .listItems)
    }

    @Test("Response parameters follow the thaw://get convention")
    func responseParametersParse() throws {
        let parsed = try #require(
            try request("thaw://list-items?callback=floe://thaw-response&requestId=abc123&broadcast=true")
        )
        #expect(parsed.callback == "floe://thaw-response")
        #expect(parsed.requestId == "abc123")
        #expect(parsed.broadcast)
        #expect(parsed.hasResponseMechanism)

        // Only the literal "true" turns broadcasting on, as for thaw://get.
        #expect(try request("thaw://list-items?broadcast=1")?.broadcast == false)
    }

    @Test("An item identifier survives percent-encoding intact")
    func itemIdentifierParses() throws {
        // Identifiers are namespace:title[:index], so they carry colons and often spaces.
        let parsed = try #require(
            try request("thaw://activate-item?item-id=com.example.app%3AStatus%20Item%3A1&callback=floe://r")
        )
        #expect(parsed.operation == .activateItem)
        #expect(parsed.identifier == "com.example.app:Status Item:1")
    }

    @Test("Each action reads only its own identifier parameter")
    func identifierParameterIsPerOperation() throws {
        #expect(try request("thaw://apply-profile?profile-id=ABC")?.identifier == "ABC")
        #expect(try request("thaw://apply-profile?item-id=ABC")?.identifier == nil)
        #expect(try request("thaw://activate-item?profile-id=ABC")?.identifier == nil)
        #expect(try request("thaw://list-items?item-id=ABC")?.identifier == nil)
    }

    @Test("An empty parameter counts as absent")
    func emptyParametersAreAbsent() throws {
        let parsed = try #require(try request("thaw://activate-item?item-id=&callback=&requestId="))
        #expect(parsed.identifier == nil)
        #expect(parsed.callback == nil)
        #expect(parsed.requestId == nil)
        #expect(!parsed.hasResponseMechanism)
    }

    // MARK: - Activation preflight

    @Test("Missing permission is reported before a missing item")
    func preflightOrdersPermissionFirst() {
        // Without Accessibility the item cache is empty, so every item looks missing.
        #expect(
            MenuBarItemManager.activationPreflight(hasAccessibilityPermission: false, itemIsLive: false)
                == .permissionMissing
        )
        #expect(
            MenuBarItemManager.activationPreflight(hasAccessibilityPermission: false, itemIsLive: true)
                == .permissionMissing
        )
        #expect(
            MenuBarItemManager.activationPreflight(hasAccessibilityPermission: true, itemIsLive: false)
                == .itemUnavailable
        )
        #expect(MenuBarItemManager.activationPreflight(hasAccessibilityPermission: true, itemIsLive: true) == nil)
    }

    // MARK: - Payloads

    @Test("The item list carries a version and only what a launcher needs")
    func itemListEncoding() throws {
        let list = LauncherURIPayload.ItemList(items: [
            LauncherURIPayload.Item(id: "com.example.app:Item-0", name: "Example", section: "hidden", bundleId: "com.example.app"),
            LauncherURIPayload.Item(id: "com.example.other:Item-0", name: "Other", section: "visible", bundleId: nil),
        ])
        let response = try wire(LauncherURIResponse.success(list, operation: .listItems, requestId: "r1"))

        #expect(response["requestId"] as? String == "r1")
        #expect(response["operation"] as? String == "list-items")
        #expect(response["status"] as? String == "success")

        let data = try #require(response["data"] as? [String: Any])
        #expect(data["version"] as? Int == 1)
        let items = try #require(data["items"] as? [[String: Any]])
        #expect(items.count == 2)
        #expect(Set(items[0].keys) == ["id", "name", "section", "bundleId"])
        #expect(items[0]["id"] as? String == "com.example.app:Item-0")
        #expect(items[0]["section"] as? String == "hidden")
        // An unknown owner is left out rather than sent as null.
        #expect(Set(items[1].keys) == ["id", "name", "section"])
    }

    @Test("The profile list marks the active profile")
    func profileListEncoding() throws {
        let work = ProfileMetadata(id: UUID(), name: "Work", createdAt: .now, modifiedAt: .now)
        let home = ProfileMetadata(id: UUID(), name: "Home", createdAt: .now, modifiedAt: .now)
        let list = LauncherURIPayload.ProfileList(profiles: [work, home], activeProfileID: home.id)
        let response = try wire(LauncherURIResponse.success(list, operation: .listProfiles, requestId: "r2"))

        let data = try #require(response["data"] as? [String: Any])
        #expect(data["version"] as? Int == 1)
        #expect(data["activeProfileId"] as? String == home.id.uuidString)
        let profiles = try #require(data["profiles"] as? [[String: Any]])
        #expect(profiles.map { $0["name"] as? String } == ["Work", "Home"])
        #expect(profiles.map { $0["isActive"] as? Bool } == [false, true])
        #expect(profiles[0]["id"] as? String == work.id.uuidString)
    }

    @Test("No profile is reported active when the active one is not in the list")
    func profileListWithoutActiveProfile() {
        let work = ProfileMetadata(id: UUID(), name: "Work", createdAt: .now, modifiedAt: .now)

        let none = LauncherURIPayload.ProfileList(profiles: [work], activeProfileID: nil)
        #expect(none.activeProfileId == nil)
        #expect(none.profiles.map(\.isActive) == [false])

        // A deleted profile's ID can outlive its manifest entry.
        let stale = LauncherURIPayload.ProfileList(profiles: [work], activeProfileID: UUID())
        #expect(stale.activeProfileId == nil)
        #expect(stale.profiles.map(\.isActive) == [false])
    }

    // MARK: - Outcome mapping

    @Test("A completed activation is a success that says whether a reaction was seen", arguments: [true, false])
    func completedActivation(reactionObserved: Bool) throws {
        let response = try wire(LauncherURIResponse.activation(
            itemId: "com.example.app:Item-0",
            outcome: .completed(reactionObserved: reactionObserved),
            requestId: "r3"
        ))

        #expect(response["status"] as? String == "success")
        #expect(response["operation"] as? String == "activate-item")
        #expect(response["error"] == nil)
        let data = try #require(response["data"] as? [String: Any])
        #expect(data["version"] as? Int == 1)
        #expect(data["itemId"] as? String == "com.example.app:Item-0")
        #expect(data["outcome"] as? String == "completed")
        #expect(data["reactionObserved"] as? Bool == reactionObserved)
    }

    @Test(
        "Each activation failure is an error with its own code",
        arguments: [
            (MenuBarItemActivationOutcome.itemUnavailable, "itemUnavailable"),
            (MenuBarItemActivationOutcome.permissionMissing, "permissionMissing"),
            (MenuBarItemActivationOutcome.activationFailed, "activationFailed"),
        ]
    )
    func failedActivation(outcome: MenuBarItemActivationOutcome, code: String) throws {
        let response = try wire(LauncherURIResponse.activation(itemId: "missing", outcome: outcome, requestId: "r4"))

        #expect(response["requestId"] as? String == "r4")
        #expect(response["status"] as? String == "error")
        #expect(response["error"] as? String == code)
        #expect((response["details"] as? String)?.isEmpty == false)
        let data = try #require(response["data"] as? [String: Any])
        #expect(data["version"] as? Int == 1)
        #expect(data["outcome"] as? String == code)
        #expect(data["itemId"] as? String == "missing")
        #expect(data["reactionObserved"] == nil)
    }

    @Test(
        "A profile application reports its outcome",
        arguments: [
            (LauncherProfileApplyOutcome.applied, "success"),
            (LauncherProfileApplyOutcome.appliedWithoutLayout, "success"),
            (LauncherProfileApplyOutcome.profileUnavailable, "error"),
            (LauncherProfileApplyOutcome.applyFailed, "error"),
        ]
    )
    func profileApplication(outcome: LauncherProfileApplyOutcome, status: String) throws {
        let response = try wire(LauncherURIResponse.profileApplication(profileId: "P", outcome: outcome, requestId: "r5"))

        #expect(response["status"] as? String == status)
        #expect(response["operation"] as? String == "apply-profile")
        #expect(outcome.isSuccess == (status == "success"))
        let data = try #require(response["data"] as? [String: Any])
        #expect(data["version"] as? Int == 1)
        #expect(data["profileId"] as? String == "P")
        #expect(data["outcome"] as? String == outcome.rawValue)
        #expect(response["error"] as? String == (status == "error" ? outcome.rawValue : nil))
    }

    @Test("A request that never reaches an outcome is an error without data")
    func requestLevelFailure() throws {
        let response = try wire(LauncherURIResponse.failure(
            LauncherURIResponse.invalidRequest,
            details: "Provide item-id=<id>",
            operation: .activateItem,
            requestId: "r6"
        ))

        #expect(response["status"] as? String == "error")
        #expect(response["error"] as? String == "invalidRequest")
        #expect(response["details"] as? String == "Provide item-id=<id>")
        #expect(response["operation"] as? String == "activate-item")
        #expect(response["data"] == nil)
    }
}
