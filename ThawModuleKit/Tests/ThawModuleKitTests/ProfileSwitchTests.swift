//
//  ProfileSwitchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
import ThawModuleKit

@Suite("Profile switch event")
struct ProfileSwitchTests {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let previousID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("A switch survives the trip through user info")
    func roundTrips() {
        let event = ProfileSwitch(profileID: id, profileName: "Work", previousProfileID: previousID, previousProfileName: "Home")
        #expect(ProfileSwitch(userInfo: event.userInfo) == event)
    }

    @Test("A first switch has no previous profile")
    func roundTripsWithoutPrevious() {
        let event = ProfileSwitch(profileID: id, profileName: "Work", previousProfileID: nil, previousProfileName: nil)
        #expect(event.userInfo.count == 2)
        #expect(ProfileSwitch(userInfo: event.userInfo) == event)
    }

    @Test("User info without a valid profile ID or name is not a switch")
    func rejectsIncompleteUserInfo() {
        #expect(ProfileSwitch(userInfo: nil) == nil)
        #expect(ProfileSwitch(userInfo: ["profileName": "Work"]) == nil)
        #expect(ProfileSwitch(userInfo: ["profileID": "not-a-uuid", "profileName": "Work"]) == nil)
        #expect(ProfileSwitch(userInfo: ["profileID": id.uuidString]) == nil)
    }

    @Test("Notification names carry the host bundle ID and the phase")
    func namesCarryHostAndPhase() {
        let name = ProfileSwitch.notificationName(.willApply, hostBundleIdentifier: "com.stonerl.Thaw.debug")
        #expect(name.rawValue == "com.stonerl.Thaw.debug.module.profile.willApply")
        #expect(name != ProfileSwitch.notificationName(.didApply, hostBundleIdentifier: "com.stonerl.Thaw.debug"))
    }
}

@Suite("Module launch environment")
struct ModuleLaunchEnvironmentTests {
    @Test("The host Thaw passes at launch wins")
    func prefersTheLaunchEnvironment() {
        let host = ModuleLaunchEnvironment.hostBundleIdentifier(
            environment: [ModuleLaunchEnvironment.hostBundleIdentifierKey: "com.example.Thaw.debug"],
            bundleIdentifier: "com.example.Thaw.module.triggers"
        )
        #expect(host == "com.example.Thaw.debug")
    }

    @Test("A module opened by hand reads the host from its own bundle ID")
    func fallsBackToTheBundleID() {
        let host = ModuleLaunchEnvironment.hostBundleIdentifier(environment: [:], bundleIdentifier: "com.example.Thaw.module.triggers")
        #expect(host == "com.example.Thaw")
    }

    @Test("A bundle ID that isn't a module's names no host")
    func noHostOutsideAModule() {
        #expect(ModuleLaunchEnvironment.hostBundleIdentifier(environment: [:], bundleIdentifier: "com.example.Other") == nil)
        #expect(ModuleLaunchEnvironment.hostBundleIdentifier(environment: [:], bundleIdentifier: nil) == nil)
    }
}
