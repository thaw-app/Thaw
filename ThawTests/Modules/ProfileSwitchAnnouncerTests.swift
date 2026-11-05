//
//  ProfileSwitchAnnouncerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawModuleKit

@MainActor
@Suite("Profile switch announcer")
struct ProfileSwitchAnnouncerTests {
    private let event = ProfileSwitch(profileID: UUID(), profileName: "Work", previousProfileID: nil, previousProfileName: nil)

    @Test("A switch is announced under Thaw's own bundle ID with the event's user info")
    func buildsTheNotification() throws {
        let notification = try #require(ProfileSwitchAnnouncer.notification(.didApply, event, hostBundleIdentifier: "com.stonerl.Thaw"))
        #expect(notification.name == ProfileSwitch.notificationName(.didApply, hostBundleIdentifier: "com.stonerl.Thaw"))
        #expect(ProfileSwitch(userInfo: notification.userInfo) == event)
    }

    @Test("Without a bundle ID nothing is announced")
    func needsABundleID() {
        #expect(ProfileSwitchAnnouncer.notification(.willApply, event, hostBundleIdentifier: nil) == nil)
    }
}
