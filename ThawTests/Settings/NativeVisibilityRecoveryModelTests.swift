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
    @MainActor
    private final class Harness {
        var conflicts: [String] = []
        var grantsAccess = true
        var nativeDisabled = false
        var inspected = false
        var restored: Set<String>?
        var failsRestore = false
        var disabled = ["com.example.recorded", "com.example.manual"]
        var recorded: Set<String> = ["com.example.recorded"]

        func model() -> NativeVisibilityRecoveryModel {
            NativeVisibilityRecoveryModel(environment: .init(
                conflictingApplications: { self.conflicts },
                disableNativeHiding: { self.nativeDisabled = true },
                requestAccess: { self.grantsAccess },
                inspect: { self.inspected = true; return (self.disabled, self.recorded) },
                restore: {
                    self.restored = $0
                    if self.failsRestore {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    return self.recorded.count + $0.count
                },
                displayName: { $0 },
                wait: {}
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
}
