//
//  ProfileSwitchTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawModuleKit

@MainActor
@Suite("Profile switch announcer", .serialized)
struct ProfileSwitchAnnouncerTests {
    private let event = ProfileSwitch(profileID: UUID(), profileName: "Work", previousProfileID: nil, previousProfileName: nil)

    /// The Scripts module's bundle ID under the test host.
    private func scriptsBundleID() throws -> String {
        try SavedScripts.domain(hostBundleIdentifier: #require(Bundle.main.bundleIdentifier))
    }

    /// Runs body with the Scripts module quit and nothing held, returning the phases it sent.
    private func sent(_ body: () throws -> Void) throws -> [ProfileSwitch.Phase] {
        var phases: [ProfileSwitch.Phase] = []
        let original = ProfileSwitchAnnouncer.deliver
        defer { ProfileSwitchAnnouncer.deliver = original }
        ProfileSwitchAnnouncer.deliver = { _, _ in }
        ProfileSwitchAnnouncer.scriptsListening()
        try ProfileSwitchAnnouncer.moduleQuit(bundleIdentifier: scriptsBundleID())
        ProfileSwitchAnnouncer.deliver = { name, _ in
            phases += [ProfileSwitch.Phase.willApply, .didApply].filter {
                ProfileSwitch.notificationName($0, hostBundleIdentifier: Bundle.main.bundleIdentifier ?? "") == name
            }
        }
        try body()
        return phases
    }

    @Test("A switch made before the Scripts module listens is sent once it does")
    func holdsUntilScriptsListens() throws {
        let phases = try sent {
            ProfileSwitchAnnouncer.post(.willApply, event)
            ProfileSwitchAnnouncer.post(.didApply, event)
            ProfileSwitchAnnouncer.scriptsListening()
        }
        #expect(phases == [.willApply, .didApply])
    }

    @Test("Nothing is sent while the Scripts module is gone")
    func holdsWhileScriptsIsGone() throws {
        let phases = try sent {
            ProfileSwitchAnnouncer.post(.willApply, event)
        }
        #expect(phases.isEmpty)
    }

    @Test("Once Scripts listens, a switch goes out at once, and another module quitting changes nothing")
    func sendsWhileListening() throws {
        let phases = try sent {
            ProfileSwitchAnnouncer.scriptsListening()
            ProfileSwitchAnnouncer.moduleQuit(bundleIdentifier: "com.example.Thaw.module.widgets")
            ProfileSwitchAnnouncer.post(.didApply, event)
        }
        #expect(phases == [.didApply])
    }

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

/// A switch made before the Scripts module listens still reaches it, once, and only while recent.
@Suite("Profile switch backlog")
struct ProfileSwitchBacklogTests {
    private let start = ContinuousClock.now
    private let work = ProfileSwitch(profileID: UUID(), profileName: "Work", previousProfileID: nil, previousProfileName: nil)
    private let home = ProfileSwitch(profileID: UUID(), profileName: "Home", previousProfileID: nil, previousProfileName: nil)

    @Test("A switch before the module listens is held, then sent in order")
    func holdsUntilListening() {
        var backlog = ProfileSwitchBacklog()
        let sendsWill = backlog.shouldSend(.willApply, work, at: start)
        let sendsDid = backlog.shouldSend(.didApply, work, at: start)
        #expect(!sendsWill && !sendsDid)

        let sent = backlog.moduleListening(at: start + .seconds(2))
        #expect(sent.map(\.phase) == [.willApply, .didApply])
        #expect(sent.map(\.event) == [work, work])
        let sentAgain = backlog.moduleListening(at: start + .seconds(3))
        #expect(sentAgain.isEmpty)
    }

    @Test("Once the module listens, switches go out straight away")
    func sendsWhileListening() {
        var backlog = ProfileSwitchBacklog()
        _ = backlog.moduleListening(at: start)
        let sendsWill = backlog.shouldSend(.willApply, work, at: start)
        let sendsDid = backlog.shouldSend(.didApply, work, at: start)
        #expect(sendsWill && sendsDid)
    }

    @Test("Only the latest switch is held")
    func keepsLatestSwitch() {
        var backlog = ProfileSwitchBacklog()
        _ = backlog.shouldSend(.willApply, work, at: start)
        _ = backlog.shouldSend(.didApply, work, at: start)
        _ = backlog.shouldSend(.willApply, home, at: start)
        _ = backlog.shouldSend(.didApply, home, at: start)
        let sent = backlog.moduleListening(at: start)
        #expect(sent.map(\.event) == [home, home])
    }

    @Test("A held switch older than a minute is dropped")
    func dropsStaleSwitch() {
        var backlog = ProfileSwitchBacklog()
        _ = backlog.shouldSend(.willApply, work, at: start)
        let sent = backlog.moduleListening(at: start + .seconds(61))
        #expect(sent.isEmpty)
    }

    @Test("After the module quits, switches wait for it again")
    func holdsAfterQuit() {
        var backlog = ProfileSwitchBacklog()
        _ = backlog.moduleListening(at: start)
        backlog.moduleStopped()
        let sends = backlog.shouldSend(.willApply, work, at: start)
        #expect(!sends)
        let sent = backlog.moduleListening(at: start)
        #expect(sent.map(\.event) == [work])
    }
}
