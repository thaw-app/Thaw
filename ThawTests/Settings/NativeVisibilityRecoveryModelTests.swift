//
//  NativeVisibilityRecoveryModelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
#if !RECOVERY_STANDALONE
    @testable import Thaw
#endif

@MainActor
struct NativeVisibilityRecoveryModelTests {
    private struct UnreadableRecord: Error {}

    @MainActor
    private final class Harness {
        var conflicts: [String] = []
        var grantsAccess = true
        var nativeDisabled = false
        var inspected = false
        var restored: Set<String>?
        var failsRestore = false
        var restoreError: Error?
        var disabled = ["com.example.recorded", "com.example.manual"]
        var recorded: Set<String> = ["com.example.recorded"]
        var recordIsUnreadable = false
        var setAsideCalls = 0
        var failsSetAside = false
        var bypassAvailable = false
        var bypassCalls = 0
        var failsBypass = false
        let bypassedRecord = URL(fileURLWithPath: "/tmp/RecoverySkipped-test/NativeAppVisibilityJournal.json")
        let movedRecord = URL(fileURLWithPath: "/tmp/NativeAppVisibilityJournal.unreadable-1.json")

        func model() -> NativeVisibilityRecoveryModel {
            NativeVisibilityRecoveryModel(environment: .init(
                conflictingApplications: { self.conflicts },
                disableNativeHiding: { self.nativeDisabled = true },
                requestAccess: { self.grantsAccess },
                inspect: {
                    self.inspected = true
                    if self.recordIsUnreadable {
                        throw UnreadableRecord()
                    }
                    return (self.disabled, self.recorded)
                },
                restore: {
                    if let error = self.restoreError {
                        throw error
                    }
                    self.restored = $0
                    if self.failsRestore {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    return self.recorded.count + $0.count
                },
                displayName: { $0 },
                wait: {},
                isUnreadableRecord: { $0 is UnreadableRecord },
                setAsideUnreadableRecords: {
                    self.setAsideCalls += 1
                    if self.failsSetAside {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    self.recordIsUnreadable = false
                    self.recorded = []
                    return [self.movedRecord]
                },
                bypassRecovery: bypassAvailable ? {
                    self.bypassCalls += 1
                    if self.failsBypass {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    self.recordIsUnreadable = false
                    self.recorded = []
                    return [self.bypassedRecord]
                } : nil
            ))
        }
    }

    @Test func explicitSelection() async {
        let harness = Harness()
        let model = harness.model()
        await model.load()
        #expect(harness.nativeDisabled)
        #expect(model.selectedBundleIDs.isEmpty)
        #expect(model.candidates.map(\.id) == ["com.example.manual"])
        #expect(model.recordedBundleIDs == ["com.example.recorded"])
        #expect(harness.restored == nil)
        model.selectedBundleIDs.insert("com.example.manual")
        await model.restore()
        #expect(harness.restored == ["com.example.manual"])
        #expect(model.successMessage != nil)
        #expect(!model.canRestore)
    }

    @Test func emptyJournalRequiresSelection() async {
        let harness = Harness()
        harness.recorded = []
        let model = harness.model()
        await model.load()
        #expect(!model.canRestore)
        await model.restore()
        #expect(harness.restored == nil)
    }

    @Test func noDisabledApps() async {
        let harness = Harness()
        harness.recorded = []
        harness.disabled = []
        let model = harness.model()
        await model.load()
        #expect(model.hasLoaded)
        #expect(model.candidates.isEmpty)
        #expect(!model.canRestore)
    }

    @Test func accessCancelled() async {
        let harness = Harness()
        harness.grantsAccess = false
        let model = harness.model()
        await model.load()
        #expect(harness.nativeDisabled)
        #expect(!harness.inspected)
        #expect(model.errorMessage != nil)
        #expect(!model.hasLoaded)
    }

    @Test func conflictingAppPreventsRecovery() async {
        let harness = Harness()
        harness.conflicts = ["Thaw"]
        let model = harness.model()
        await model.load()
        #expect(!harness.nativeDisabled)
        #expect(!harness.inspected)
        #expect(model.errorMessage != nil)
    }

    @Test func conflictAfterInspectionPreventsWrite() async {
        let harness = Harness()
        let model = harness.model()
        await model.load()
        harness.conflicts = ["Bartender"]
        await model.restore()
        #expect(harness.restored == nil)
        #expect(model.errorMessage != nil)
    }

    @Test func failedRestoreKeepsSelectionForRetry() async {
        let harness = Harness()
        harness.failsRestore = true
        let model = harness.model()
        await model.load()
        model.selectedBundleIDs = ["com.example.manual"]
        await model.restore()
        #expect(model.errorMessage != nil)
        #expect(model.successMessage == nil)
        #expect(model.selectedBundleIDs == ["com.example.manual"])
        #expect(model.recordedBundleIDs == ["com.example.recorded"])
        #expect(model.canRestore)
    }

    @Test func unreadableRecordShowsNoAppList() async {
        let harness = Harness()
        harness.recordIsUnreadable = true
        let model = harness.model()
        await model.load()
        #expect(model.recordIsUnreadable)
        #expect(model.errorMessage == nil)
        #expect(!model.hasLoaded)
        #expect(model.candidates.isEmpty)
        #expect(!model.canRestore)
        #expect(harness.setAsideCalls == 0, "Nothing is moved before the user confirms")
    }

    @Test func settingAsideListsEveryDisabledAppUnselected() async {
        let harness = Harness()
        harness.recordIsUnreadable = true
        let model = harness.model()
        await model.load()
        model.setAsideUnreadableRecords()
        #expect(harness.setAsideCalls == 1)
        #expect(!model.recordIsUnreadable)
        #expect(model.setAsideLocations == [harness.movedRecord])
        #expect(model.hasLoaded)
        #expect(model.recordedBundleIDs.isEmpty)
        #expect(model.candidates.map(\.id) == ["com.example.recorded", "com.example.manual"])
        #expect(model.selectedBundleIDs.isEmpty)
        #expect(!model.canRestore)
        model.selectedBundleIDs = ["com.example.manual"]
        await model.restore()
        #expect(harness.restored == ["com.example.manual"])
    }

    @Test func setAsideDoesNothingWhileTheRecordIsReadable() async {
        let harness = Harness()
        let model = harness.model()
        await model.load()
        model.setAsideUnreadableRecords()
        #expect(harness.setAsideCalls == 0)
        #expect(model.setAsideLocations.isEmpty)
    }

    @Test func failedSetAsideKeepsTheExplanation() async {
        let harness = Harness()
        harness.recordIsUnreadable = true
        harness.failsSetAside = true
        let model = harness.model()
        await model.load()
        model.setAsideUnreadableRecords()
        #expect(model.recordIsUnreadable)
        #expect(model.errorMessage != nil)
        #expect(!model.hasLoaded)
    }

    @Test func setAsideWaitsForOtherCopiesToQuit() async {
        let harness = Harness()
        harness.recordIsUnreadable = true
        let model = harness.model()
        await model.load()
        harness.conflicts = ["Thaw"]
        model.setAsideUnreadableRecords()
        #expect(harness.setAsideCalls == 0)
        #expect(model.recordIsUnreadable)
        #expect(model.errorMessage != nil)
    }

    @Test func recordTurningUnreadableBeforeRestoreHidesTheList() async {
        let harness = Harness()
        let model = harness.model()
        await model.load()
        model.selectedBundleIDs = ["com.example.manual"]
        harness.recordIsUnreadable = true
        harness.restoreError = UnreadableRecord()
        await model.restore()
        #expect(model.recordIsUnreadable)
        #expect(!model.hasLoaded)
        #expect(model.candidates.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func olderRuntimesDoNotOfferBypass() async {
        let harness = Harness()
        let model = harness.model()
        await model.load()
        #expect(!model.supportsRecoveryBypass)
        model.bypassRecovery()
        #expect(harness.bypassCalls == 0)
        #expect(model.recordedBundleIDs == ["com.example.recorded"])
    }

    @Test func confirmedBypassKeepsBackupsAndLeavesNativeOff() async {
        let harness = Harness()
        harness.bypassAvailable = true
        let model = harness.model()
        await model.load()
        #expect(model.supportsRecoveryBypass)
        #expect(harness.bypassCalls == 0)
        model.selectedBundleIDs = ["com.example.manual"]

        model.bypassRecovery()

        #expect(harness.bypassCalls == 1)
        #expect(harness.nativeDisabled)
        #expect(harness.restored == nil)
        #expect(model.setAsideLocations == [harness.bypassedRecord])
        #expect(model.recordedBundleIDs.isEmpty)
        #expect(model.selectedBundleIDs.isEmpty)
        #expect(model.candidates.isEmpty)
        #expect(!model.hasLoaded)
        #expect(!model.canRestore)
        #expect(model.successMessage != nil)
    }

    @Test func bypassDoesNotRequireControlCenterAccess() async {
        let harness = Harness()
        harness.bypassAvailable = true
        harness.grantsAccess = false
        let model = harness.model()
        await model.load()
        #expect(model.errorMessage != nil)

        model.bypassRecovery()

        #expect(harness.bypassCalls == 1)
        #expect(!harness.inspected)
        #expect(model.successMessage != nil)
        #expect(model.errorMessage == nil)
    }

    @Test func bypassAlsoWorksWhenTheRecordIsUnreadable() async {
        let harness = Harness()
        harness.bypassAvailable = true
        harness.recordIsUnreadable = true
        let model = harness.model()
        await model.load()
        #expect(model.recordIsUnreadable)

        model.bypassRecovery()

        #expect(!model.recordIsUnreadable)
        #expect(model.successMessage != nil)
        #expect(model.setAsideLocations == [harness.bypassedRecord])
    }

    @Test func failedBypassPreservesTheRecoveryChoices() async {
        let harness = Harness()
        harness.bypassAvailable = true
        harness.failsBypass = true
        let model = harness.model()
        await model.load()
        model.selectedBundleIDs = ["com.example.manual"]

        model.bypassRecovery()

        #expect(model.errorMessage != nil)
        #expect(model.successMessage == nil)
        #expect(model.recordedBundleIDs == ["com.example.recorded"])
        #expect(model.selectedBundleIDs == ["com.example.manual"])
        #expect(model.canRestore)
        #expect(model.setAsideLocations.isEmpty)
    }

    @Test func bypassWaitsForOtherHidingManagersToQuit() async {
        let harness = Harness()
        harness.bypassAvailable = true
        let model = harness.model()
        await model.load()
        harness.conflicts = ["Bartender"]

        model.bypassRecovery()

        #expect(harness.bypassCalls == 0)
        #expect(model.errorMessage != nil)
        #expect(model.successMessage == nil)
        #expect(model.recordedBundleIDs == ["com.example.recorded"])
    }
}
