//
//  HidingMethodTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
import Testing
@testable import Thaw

@MainActor
@Suite("One hiding method runs at a time")
struct HidingMethodTests {
    @Test("The native switch picks the method, and each method writes the switch it was read from", arguments: HidingMethod.allCases)
    func nativeSwitchPicksTheMethod(method: HidingMethod) {
        #expect(HidingMethod(nativeAppHidingEnabled: true) == .native)
        #expect(HidingMethod(nativeAppHidingEnabled: false) == .standard)
        #expect(HidingMethod(nativeAppHidingEnabled: method.usesNativeAppHiding) == method)
    }

    @Test("Standard hides Clock, Control Center and Siri, and Native cannot")
    func standardHidesAppleItems() {
        #expect(HidingMethod.standard.hidesAppleItems)
        #expect(!HidingMethod.native.hidesAppleItems)
    }

    @Test("Every method has its own identity, name and one-line explanation")
    func methodsAreTellableApart() {
        let methods = HidingMethod.allCases
        #expect(Set(methods.map(\.id)).count == methods.count)
        #expect(Set(methods.map { "\($0.localized)" }).count == methods.count)
        let explanations = methods.map { "\($0.explanation)" }
        #expect(Set(explanations).count == methods.count)
        // The costs are left to the limitations popover.
        #expect(explanations.allSatisfy { !$0.contains("\\n") && !$0.contains("\n") })
    }
}

@MainActor
@Suite("A failed start of native hiding does not lose the user's choice")
struct NativeHidingStartTests {
    @Test("A start that fails at launch keeps the choice; one the user just asked for goes back to off")
    func failedStartKeepsOnlyTheLaunchChoice() {
        #expect(NativeHidingStart.keepsChoice(afterFailedStartAtLaunch: true))
        #expect(!NativeHidingStart.keepsChoice(afterFailedStartAtLaunch: false))
    }

    @Test("A failed start says why, or that macOS gave no reason")
    func failureNoticeSaysWhy() {
        let reason = NativeAppVisibilityStoreError.anotherProcessOwnsNativeHiding.localizedDescription
        #expect(NativeHidingStart.failureNotice(reason: reason).hasSuffix(reason))
        #expect(NativeHidingStart.failureNotice(reason: nil).hasSuffix("macOS gave no reason."))
        #expect(NativeHidingStart.failureNotice(reason: nil).contains("using Standard"))
    }

    @Test(
        "Settings gives the reason Native fell back only while Native is chosen, not running, and the record is readable",
        arguments: [
            (true, false, false, true),
            (true, true, false, false),
            (false, false, false, false),
            // An unreadable record has its own notice, so no fallback reason repeats it.
            (true, false, true, false),
        ]
    )
    func fallbackReason(nativeChosen: Bool, isActive: Bool, journalNeedsAttention: Bool, givesReason: Bool) {
        let reason = "Another copy of Thaw is showing and hiding menu bar apps."
        let shown = NativeHidingStart.fallbackReason(
            nativeChosen: nativeChosen, isActive: isActive, journalNeedsAttention: journalNeedsAttention, lastError: reason
        )
        #expect(shown == (givesReason ? reason : nil))
    }

    @Test("The hiding method is locked while the record is unreadable")
    func methodLockedWhileRecordIsUnreadable() {
        #expect(!NativeHidingStart.allowsMethodChange(journalNeedsAttention: true))
        #expect(NativeHidingStart.allowsMethodChange(journalNeedsAttention: false))
    }

    @Test("Before any start, native hiding is off and reports no failure, recovery problem or unreadable record")
    func unstartedExperimentIsQuiet() {
        let experiment = NativeAppHidingExperiment()
        #expect(!experiment.isActive)
        #expect(experiment.lastError == nil)
        #expect(!experiment.previousSessionRecoveryFailed)
        #expect(!experiment.journalNeedsAttention)
        #expect(experiment.failedStartNotice == nil)
    }
}
