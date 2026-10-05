//
//  LauncherURITestSupport.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Parent of every suite that swaps the response delivery hooks, so none of
/// them runs while another has its own capture installed.
@Suite("Settings URI responses", .serialized)
enum SettingsURIResponseSuites {}

/// Records the responses SettingsURIHandler would send instead of sending them:
/// no URL is opened and nothing reaches the distributed notification center.
@MainActor
final class URIDeliveryCapture {
    private(set) var openedURLs = [URL]()
    private(set) var broadcasts = [String]()
    var openSucceeds = true

    func run<T>(_ body: () async throws -> T) async rethrows -> T {
        let previousOpen = SettingsURIHandler.openCallbackURL
        let previousPost = SettingsURIHandler.postBroadcastJSON
        SettingsURIHandler.openCallbackURL = { [self] url in
            openedURLs.append(url)
            return openSucceeds
        }
        SettingsURIHandler.postBroadcastJSON = { [self] json in
            broadcasts.append(json)
        }
        defer {
            SettingsURIHandler.openCallbackURL = previousOpen
            SettingsURIHandler.postBroadcastJSON = previousPost
        }
        return try await body()
    }

    /// The response a callback receiver would decode from the data parameter.
    func callbackResponse(at index: Int = 0) throws -> [String: Any] {
        try #require(openedURLs.count > index, "No callback was opened")
        let components = try #require(URLComponents(url: openedURLs[index], resolvingAgainstBaseURL: false))
        let json = try #require(components.queryItems?.first { $0.name == "data" }?.value)
        return try Self.object(json)
    }

    func broadcastResponse(at index: Int = 0) throws -> [String: Any] {
        try #require(broadcasts.count > index, "Nothing was broadcast")
        return try Self.object(broadcasts[index])
    }

    private static func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }
}

/// A launcher environment whose state the test sets and whose calls it can count.
@MainActor
final class FakeLauncherEnvironment {
    struct ApplyFailure: Error {}

    var hasPermission = true
    var items = [LauncherURIPayload.Item]()
    var profiles = [ProfileMetadata]()
    var activeProfileID: UUID?
    var activationOutcome = MenuBarItemActivationOutcome.completed(reactionObserved: true)
    /// Whether the layout half ran; nil makes the apply throw.
    var applyLayoutRan: Bool? = true

    private(set) var itemReads = 0
    private(set) var profileReads = 0
    private(set) var appearanceReads = 0
    private(set) var activatedIdentifiers = [String]()
    private(set) var appliedProfileIDs = [UUID]()

    let appearance = SharedAppearance(
        configuration: .defaultConfiguration,
        shapeKind: .notch,
        hasRoundedShape: true,
        isDark: true
    )

    var environment: SettingsURIHandler.LauncherEnvironment {
        SettingsURIHandler.LauncherEnvironment(
            hasAccessibilityPermission: { self.hasPermission },
            items: {
                self.itemReads += 1
                return self.items
            },
            appearance: {
                self.appearanceReads += 1
                return self.appearance
            },
            profiles: {
                self.profileReads += 1
                return self.profiles
            },
            activeProfileID: { self.activeProfileID },
            activateItem: { identifier in
                self.activatedIdentifiers.append(identifier)
                return self.activationOutcome
            },
            applyProfile: { profileID in
                self.appliedProfileIDs.append(profileID)
                guard let ran = self.applyLayoutRan else { throw ApplyFailure() }
                return ran
            }
        )
    }

    @discardableResult
    func addProfile(named name: String, active: Bool = false) -> UUID {
        let id = UUID()
        profiles.append(ProfileMetadata(id: id, name: name, createdAt: .distantPast, modifiedAt: .distantPast))
        if active {
            activeProfileID = id
        }
        return id
    }

    /// Sends one thaw:// URL through the handler and returns what it delivered.
    func send(_ string: String) async throws -> URIDeliveryCapture {
        let url = try #require(URL(string: string))
        let request = try #require(LauncherURIRequest(url: url))
        let capture = URIDeliveryCapture()
        await capture.run {
            await SettingsURIHandler.handleLauncherRequest(request, sender: "com.example.launcher", environment: environment)
        }
        return capture
    }
}
