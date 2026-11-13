//
//  LeadingEdgePollIntervalTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Testing
@testable import Thaw

@Suite("Leading edge poll interval")
struct LeadingEdgePollIntervalTests {
    private let now = ContinuousClock.now

    @Test("An idle bar is polled at the idle interval")
    func idleWithoutAWindow() {
        let interval = MenuBarLeadingEdgeWatcher.pollInterval(now: now, fastUntil: nil)
        #expect(interval == MenuBarLeadingEdgeWatcher.pollInterval)
    }

    @Test("Inside the window after a change the bar is polled fast")
    func fastInsideTheWindow() {
        let interval = MenuBarLeadingEdgeWatcher.pollInterval(now: now, fastUntil: now + .seconds(1))
        #expect(interval == MenuBarLeadingEdgeWatcher.fastPollInterval)
    }

    @Test("Once the window has passed polling returns to idle")
    func idleAfterTheWindow() {
        let interval = MenuBarLeadingEdgeWatcher.pollInterval(now: now, fastUntil: now - .milliseconds(1))
        #expect(interval == MenuBarLeadingEdgeWatcher.pollInterval)
    }

    @MainActor
    @Test("Expecting a change opens the fast window, and expecting another extends it")
    func expectChangeOpensAndExtendsTheWindow() throws {
        let watcher = MenuBarLeadingEdgeWatcher()
        #expect(watcher.fastPollUntil == nil, "A watcher nobody warned polls at the idle interval")

        let before = ContinuousClock.now
        watcher.expectChange()
        let after = ContinuousClock.now
        let first = try #require(watcher.fastPollUntil)
        #expect(first >= before + MenuBarLeadingEdgeWatcher.fastPollWindow)
        #expect(first <= after + MenuBarLeadingEdgeWatcher.fastPollWindow)
        #expect(MenuBarLeadingEdgeWatcher.pollInterval(now: after, fastUntil: first) == MenuBarLeadingEdgeWatcher.fastPollInterval)

        watcher.expectChange()
        let second = try #require(watcher.fastPollUntil)
        #expect(second >= first, "A later sign of change must never shorten the window")
        #expect(watcher.leadingEdge == nil, "Expecting a change is not itself a reading")
    }
}

@Suite("Leading edge followers")
struct LeadingEdgeFollowersTests {
    @Test("The first follower starts polling and the last one stops it")
    func firstStartsLastStops() {
        var followers = LeadingEdgeFollowers()
        let first = UUID()
        let second = UUID()
        #expect(!followers.isFollowed)
        #expect(followers.add(first) == .start)
        #expect(followers.add(second) == .none)
        #expect(followers.remove(first) == .none)
        #expect(followers.isFollowed)
        #expect(followers.remove(second) == .stop)
        #expect(!followers.isFollowed)
    }

    @Test("A follower removed twice, or never added, cannot stop polling for the others")
    func repeatedRemovalIsIgnored() {
        var followers = LeadingEdgeFollowers()
        let staying = UUID()
        let leaving = UUID()
        _ = followers.add(staying)
        _ = followers.add(leaving)
        #expect(followers.remove(leaving) == .none)
        #expect(followers.remove(leaving) == .none)
        #expect(followers.remove(UUID()) == .none)
        #expect(followers.isFollowed)
    }

    @Test("Adding a follower that is already following changes nothing")
    func repeatedAddIsIgnored() {
        var followers = LeadingEdgeFollowers()
        let id = UUID()
        #expect(followers.add(id) == .start)
        #expect(followers.add(id) == .none)
        #expect(followers.remove(id) == .stop)
    }

    @MainActor
    @Test("Without a follower the edge is not polled, even when a change is expected")
    func noFollowerNoPolling() {
        let watcher = MenuBarLeadingEdgeWatcher()
        #expect(!watcher.isPolling)
        watcher.expectChange()
        #expect(!watcher.isPolling)
        #expect(watcher.fastPollUntil != nil, "The window is still noted for a follower that arrives inside it")
    }

    @MainActor
    @Test("Polling runs while any follower holds its token, in the fast window from the start")
    func pollingFollowsTheTokens() throws {
        let watcher = MenuBarLeadingEdgeWatcher()
        let before = ContinuousClock.now
        let first = watcher.follow { _ in }
        #expect(watcher.isPolling)
        let fastUntil = try #require(watcher.fastPollUntil)
        #expect(fastUntil >= before + MenuBarLeadingEdgeWatcher.fastPollWindow, "A new follower gets fast reads")

        var second: AnyCancellable? = watcher.follow { _ in }
        first.cancel()
        #expect(watcher.isPolling && second != nil, "One follower leaving does not stop the other's polling")
        first.cancel()
        #expect(watcher.isPolling, "Cancelling a token twice must not count as a second follower leaving")

        second = nil
        #expect(!watcher.isPolling, "A released token stops polling like a cancelled one")
        #expect(watcher.leadingEdge == nil)

        watcher.expectChange()
        #expect(!watcher.isPolling, "Expecting a change after the last follower left does not restart polling")

        let again = watcher.follow { _ in }
        #expect(watcher.isPolling, "A follower arriving later starts polling again")
        again.cancel()
        #expect(!watcher.isPolling)
    }

    @MainActor
    @Test("A follow holds its token only while wanted and while there is a watcher")
    func followHoldsItsTokenOnlyWhileWanted() {
        let watcher = MenuBarLeadingEdgeWatcher()
        let follow = LeadingEdgeFollow { _ in }
        follow.update(watcher, wanted: false)
        #expect(!watcher.isPolling, "A shape that spans the bar asks no app for the edge")

        follow.update(watcher, wanted: true)
        follow.update(watcher, wanted: true)
        #expect(watcher.isPolling)

        follow.update(watcher, wanted: false)
        #expect(!watcher.isPolling, "Wanting twice took one token, so one release stops polling")

        follow.update(watcher, wanted: true)
        follow.update(nil, wanted: true)
        #expect(!watcher.isPolling, "A panel that left its window stops following")
    }
}
