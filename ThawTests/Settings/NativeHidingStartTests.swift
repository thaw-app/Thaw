//
//  NativeHidingStartTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import PlatformRuntimeKit
import Testing
@testable import Thaw

@MainActor
@Suite("A failed start of native hiding does not lose the user's choice")
struct NativeHidingStartTests {
    @Test("A start that fails at launch keeps the choice")
    func launchFailureKeepsTheChoice() {
        #expect(NativeHidingStart.keepsChoice(afterFailedStartAtLaunch: true))
    }

    @Test("A start the user just asked for goes back to off when it fails")
    func userStartFailureTurnsItOff() {
        #expect(!NativeHidingStart.keepsChoice(afterFailedStartAtLaunch: false))
    }

    @Test("A failed start says why, or that macOS gave no reason")
    func failureNoticeSaysWhy() {
        let reason = "Thaw can't read Control Center's settings."
        #expect(NativeHidingStart.failureNotice(reason: reason).hasSuffix(reason))
        #expect(NativeHidingStart.failureNotice(reason: nil).hasSuffix("macOS gave no reason."))
        #expect(NativeHidingStart.failureNotice(reason: nil).contains("using Standard"))
    }

    @Test("Settings gives the reason Native fell back only while Native is chosen and not running")
    func fallbackReasonOnlyWhileChosenAndStopped() {
        let reason = "Another copy of Thaw is showing and hiding menu bar apps."
        #expect(NativeHidingStart.fallbackReason(
            nativeChosen: true, isActive: false, journalNeedsAttention: false, lastError: reason
        ) == reason)
        #expect(NativeHidingStart.fallbackReason(
            nativeChosen: true, isActive: true, journalNeedsAttention: false, lastError: reason
        ) == nil)
        #expect(NativeHidingStart.fallbackReason(
            nativeChosen: false, isActive: false, journalNeedsAttention: false, lastError: reason
        ) == nil)
    }

    @Test("An unreadable record has its own notice, so no fallback reason repeats it")
    func unreadableRecordGivesNoFallbackReason() {
        #expect(NativeHidingStart.fallbackReason(
            nativeChosen: true, isActive: false, journalNeedsAttention: true, lastError: "unreadable"
        ) == nil)
    }

    @Test("The hiding method is locked while the record is unreadable")
    func methodLockedWhileRecordIsUnreadable() {
        #expect(!NativeHidingStart.allowsMethodChange(journalNeedsAttention: true))
        #expect(NativeHidingStart.allowsMethodChange(journalNeedsAttention: false))
    }

    @Test("A second copy holding native hiding reads as a reason in the failure notice")
    func anotherCopyReadsAsAReason() {
        let reason = NativeAppVisibilityStoreError.anotherProcessOwnsNativeHiding.localizedDescription
        let notice = NativeHidingStart.failureNotice(reason: reason)
        #expect(notice.hasSuffix(reason))
        #expect(reason.contains("Another copy"))
    }
}
