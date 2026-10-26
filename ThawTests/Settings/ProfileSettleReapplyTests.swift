//
//  ProfileSettleReapplyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// The end of a settle re-applies the active profile only when it is not the one already in place.
@MainActor
@Suite("Profile re-apply after settling")
struct ProfileSettleReapplyTests {
    private let work = UUID()
    private let home = UUID()
    private let suites = ScratchSuites(prefix: "ProfileSettleReapplyTests")

    private func freshDefaults() -> UserDefaults {
        suites.make()!
    }

    @Test("No active profile, nothing to apply")
    func noActiveProfile() {
        #expect(!ProfileSettleReapply.shouldReapply(activeProfileID: nil, lastSettledProfileID: nil))
        #expect(!ProfileSettleReapply.shouldReapply(activeProfileID: nil, lastSettledProfileID: work))
    }

    @Test("A profile never applied at a settle is applied")
    func firstSettleApplies() {
        #expect(ProfileSettleReapply.shouldReapply(activeProfileID: work, lastSettledProfileID: nil))
    }

    @Test("The same profile again is left alone, so a drag since it was applied survives")
    func sameProfileIsSkipped() {
        #expect(!ProfileSettleReapply.shouldReapply(activeProfileID: work, lastSettledProfileID: work))
    }

    @Test("A different profile is applied")
    func changedProfileApplies() {
        #expect(ProfileSettleReapply.shouldReapply(activeProfileID: home, lastSettledProfileID: work))
    }

    @Test("A display switch whose apply is still running is left to finish, not applied a second time")
    func pendingApplyOfTheActiveProfileIsLeftToFinish() {
        #expect(ProfileSettleReapply.step(
            activeProfileID: home, lastSettledProfileID: work, pendingApplyProfileID: home
        ) == .leavePendingApply)
    }

    @Test("A pending apply of another profile still leaves the active one to apply")
    func pendingApplyOfAnotherProfileReapplies() {
        #expect(ProfileSettleReapply.step(
            activeProfileID: home, lastSettledProfileID: work, pendingApplyProfileID: work
        ) == .reapply)
    }

    @Test("Without a pending apply the step follows shouldReapply", arguments: [false, true])
    func noPendingApplyFollowsShouldReapply(changed: Bool) {
        let last = changed ? work : home
        #expect(ProfileSettleReapply.step(
            activeProfileID: home, lastSettledProfileID: last, pendingApplyProfileID: nil
        ) == (changed ? .reapply : .keep))
    }

    @Test("No active profile keeps, whatever is pending")
    func noActiveProfileKeeps() {
        #expect(ProfileSettleReapply.step(
            activeProfileID: nil, lastSettledProfileID: work, pendingApplyProfileID: home
        ) == .keep)
    }

    @Test("Settling while the active profile's apply is pending records it and leaves the apply running")
    func settleRecordsAPendingApply() {
        let record = ProfileSettleReapply.Record(defaults: freshDefaults())
        record.lastSettledProfileID = work
        #expect(record.settle(activeProfileID: home, pendingApplyProfileID: home) == .leavePendingApply)
        #expect(record.lastSettledProfileID == home)
    }

    @Test("Without a store given, the record keeps to the app's defaults store")
    func recordUsesAppStore() {
        let defaults = freshDefaults()
        let previous = Defaults.store
        Defaults.store = defaults
        defer { Defaults.store = previous }
        ProfileSettleReapply.Record().lastSettledProfileID = work
        #expect(ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID == work)
    }

    @Test("The record starts empty")
    func recordStartsEmpty() {
        let record = ProfileSettleReapply.Record(defaults: freshDefaults())
        #expect(record.lastSettledProfileID == nil)
    }

    @Test("The record keeps the last profile across launches")
    func recordPersists() {
        let defaults = freshDefaults()
        let record = ProfileSettleReapply.Record(defaults: defaults)
        record.lastSettledProfileID = work
        #expect(ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID == work)
    }

    @Test("Clearing the record forgets the profile")
    func recordClears() {
        let defaults = freshDefaults()
        let record = ProfileSettleReapply.Record(defaults: defaults)
        record.lastSettledProfileID = work
        record.lastSettledProfileID = nil
        #expect(ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID == nil)
    }

    @Test("A malformed stored value reads as no profile")
    func malformedValueReadsAsNil() {
        let defaults = freshDefaults()
        defaults.set("not a uuid", forKey: ProfileSettleReapply.Record.key)
        #expect(ProfileSettleReapply.Record(defaults: defaults).lastSettledProfileID == nil)
    }

    @Test("Each settle in turn: first applies, repeats skip, a switch applies once")
    func settleSequence() {
        let record = ProfileSettleReapply.Record(defaults: freshDefaults())
        var applied = [UUID]()
        for active in [work, work, work, home, home, work] {
            if record.settle(activeProfileID: active) {
                applied.append(active)
            }
        }
        #expect(applied == [work, home, work])
    }

    @Test("Settling with no active profile forgets the last one")
    func settleWithoutProfileForgets() {
        let record = ProfileSettleReapply.Record(defaults: freshDefaults())
        #expect(record.settle(activeProfileID: work))
        #expect(!record.settle(activeProfileID: nil))
        #expect(record.lastSettledProfileID == nil)
        #expect(record.settle(activeProfileID: work))
    }
}
