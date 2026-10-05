//
//  LauncherURIActionHandlingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

extension SettingsURIResponseSuites {
    /// The two launcher operations that act: what they do with an identifier and how each outcome is reported.
    @MainActor
    @Suite("Launcher URI actions")
    struct LauncherURIActionHandlingTests {
        private let callback = "callback=floe://thaw-response"

        @Test("activate-item presses the named item and reports a delivered press as success", arguments: [true, false])
        func activateItemReportsCompletion(reactionObserved: Bool) async throws {
            let fake = FakeLauncherEnvironment()
            fake.activationOutcome = .completed(reactionObserved: reactionObserved)
            let capture = try await fake.send("thaw://activate-item?item-id=com.example.app:Item&\(callback)&requestId=r1")

            #expect(fake.activatedIdentifiers == ["com.example.app:Item"])
            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "success")
            #expect(response["operation"] as? String == "activate-item")
            #expect(response["requestId"] as? String == "r1")
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["itemId"] as? String == "com.example.app:Item")
            #expect(data["outcome"] as? String == "completed")
            #expect(data["reactionObserved"] as? Bool == reactionObserved)
        }

        @Test("An activation that did not happen is an error named after its outcome", arguments: [
            (MenuBarItemActivationOutcome.itemUnavailable, "itemUnavailable"),
            (.permissionMissing, "permissionMissing"),
            (.activationFailed, "activationFailed"),
        ])
        func activateItemReportsFailure(outcome: MenuBarItemActivationOutcome, code: String) async throws {
            let fake = FakeLauncherEnvironment()
            fake.activationOutcome = outcome
            let capture = try await fake.send("thaw://activate-item?item-id=gone&\(callback)")

            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "error")
            #expect(response["error"] as? String == code)
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["outcome"] as? String == code)
            #expect(data["reactionObserved"] == nil)
        }

        @Test("An action runs even when the caller asked for no response")
        func actionRunsWithoutResponseMechanism() async throws {
            let fake = FakeLauncherEnvironment()
            let profile = fake.addProfile(named: "Work")
            let activation = try await fake.send("thaw://activate-item?item-id=com.example.app:Item")
            let application = try await fake.send("thaw://apply-profile?profile-id=\(profile.uuidString)")

            #expect(fake.activatedIdentifiers == ["com.example.app:Item"])
            #expect(fake.appliedProfileIDs == [profile])
            for capture in [activation, application] {
                #expect(capture.openedURLs.isEmpty)
                #expect(capture.broadcasts.isEmpty)
            }
        }

        @Test("An action without its identifier is refused before anything is touched", arguments: [
            (LauncherURIOperation.activateItem, "item-id"),
            (.applyProfile, "profile-id"),
        ])
        func missingIdentifierIsAnInvalidRequest(operation: LauncherURIOperation, parameter: String) async throws {
            let fake = FakeLauncherEnvironment()
            fake.addProfile(named: "Work")
            let capture = try await fake.send("thaw://\(operation.rawValue)?\(callback)&\(parameter)=")

            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "error")
            #expect(response["operation"] as? String == operation.rawValue)
            #expect(response["error"] as? String == LauncherURIResponse.invalidRequest)
            #expect((response["details"] as? String)?.contains(parameter) == true)
            #expect(fake.activatedIdentifiers.isEmpty)
            #expect(fake.appliedProfileIDs.isEmpty)
        }

        @Test("apply-profile reports whether the layout half ran", arguments: [
            (true, "applied"),
            (false, "appliedWithoutLayout"),
        ])
        func applyProfileReportsLayout(layoutRan: Bool, outcome: String) async throws {
            let fake = FakeLauncherEnvironment()
            let profile = fake.addProfile(named: "Work")
            fake.applyLayoutRan = layoutRan
            let capture = try await fake.send("thaw://apply-profile?profile-id=\(profile.uuidString)&\(callback)")

            #expect(fake.appliedProfileIDs == [profile])
            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "success")
            #expect(response["operation"] as? String == "apply-profile")
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["profileId"] as? String == profile.uuidString)
            #expect(data["outcome"] as? String == outcome)
        }

        @Test("A profile that cannot be loaded is reported as a failed apply")
        func applyProfileReportsLoadFailure() async throws {
            let fake = FakeLauncherEnvironment()
            let profile = fake.addProfile(named: "Work")
            fake.applyLayoutRan = nil
            let capture = try await fake.send("thaw://apply-profile?profile-id=\(profile.uuidString)&\(callback)")

            #expect(fake.appliedProfileIDs == [profile])
            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "error")
            #expect(response["error"] as? String == "applyFailed")
        }

        @Test("An identifier that names no saved profile applies nothing", arguments: [
            "not-a-uuid", "7E0B0E2B-4E57-4B43-9C7E-3D2D6A1B5C10",
        ])
        func unknownProfileIsUnavailable(identifier: String) async throws {
            let fake = FakeLauncherEnvironment()
            fake.addProfile(named: "Work")
            let capture = try await fake.send("thaw://apply-profile?profile-id=\(identifier)&\(callback)")

            #expect(fake.appliedProfileIDs.isEmpty)
            let response = try capture.callbackResponse()
            #expect(response["status"] as? String == "error")
            #expect(response["error"] as? String == "profileUnavailable")
            let data = try #require(response["data"] as? [String: Any])
            #expect(data["profileId"] as? String == identifier)
        }

        @Test("An action answers a broadcast with an acknowledgement only")
        func actionBroadcastIsAnAcknowledgement() async throws {
            let fake = FakeLauncherEnvironment()
            fake.activationOutcome = .activationFailed
            let capture = try await fake.send("thaw://activate-item?item-id=com.example.app:Item&broadcast=true")

            #expect(fake.activatedIdentifiers == ["com.example.app:Item"])
            let response = try capture.broadcastResponse()
            #expect(response["status"] as? String == "ack")
            #expect(response["error"] == nil, "The outcome goes only to a callback")
        }
    }
}
