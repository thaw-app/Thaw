//
//  ProfileSwitchBacklogTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import ThawModuleKit

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
        #expect(sentAgain.isEmpty, "sent once")
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
