//
//  ProfileDisplayChoicesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Profile display picker")
struct ProfileDisplayChoicesTests {
    private typealias DisplayInfo = DisplaySettingsManager.DisplayInfo

    private static func profile(displayUUID: String?, displayName: String? = nil) -> ProfileMetadata {
        var profile = ProfileMetadata(id: UUID(), name: "Profile", createdAt: .distantPast, modifiedAt: .distantPast)
        profile.associatedDisplayUUID = displayUUID
        profile.associatedDisplayName = displayName
        return profile
    }

    private static let builtIn = DisplayInfo(id: "built-in", displayID: 1, name: "Built-in Display", hasNotch: true, isConnected: true)

    @Test("Connected displays come first, then a disconnected one a profile still names")
    func keepsDisconnectedChoices() {
        let choices = ProfileSwitchesSection.displayChoices(
            connected: [Self.builtIn],
            profiles: [
                Self.profile(displayUUID: "built-in", displayName: "Old Name"),
                Self.profile(displayUUID: "studio", displayName: "Studio Display"),
                Self.profile(displayUUID: "studio", displayName: "Studio Display"),
                Self.profile(displayUUID: "unnamed"),
                Self.profile(displayUUID: nil),
            ]
        )
        #expect(choices.map(\.id) == ["built-in", "studio", "unnamed"])
        #expect(choices[0].name == "Built-in Display")
        #expect(choices[1].name == "Studio Display")
        #expect(choices[1].isConnected == false)
        #expect(choices[1].displayID == nil)
        #expect(choices[2].name == "unnamed")
    }

    @Test("The label names the notch and a disconnected display")
    func labels() {
        let studio = DisplayInfo(id: "studio", displayID: nil, name: "Studio Display", hasNotch: false, isConnected: false)
        #expect(ProfileSwitchesSection.label(for: Self.builtIn) == "Built-in Display · Notch")
        #expect(ProfileSwitchesSection.label(for: studio) == "Studio Display · Disconnected")
    }
}
