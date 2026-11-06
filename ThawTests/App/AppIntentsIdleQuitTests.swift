//
//  AppIntentsIdleQuitTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreServices
import Foundation
import Security
import Testing
@testable import Thaw

/// 2026-11-05: after a restart, an ad-hoc signed local build started at login quit about a
/// minute later. linkd had turned down its App Intents registration for want of a team, ran
/// the Focus filter in it as if it had launched Thaw, and then sent a quit.
@Suite("Thaw stays running when App Intents asks it to quit")
struct AppIntentsIdleQuitTests {
    /// A core Apple event with this ID that names no sender, carrying a quit reason when one is given.
    private static func event(_ eventID: AEEventID, reason: OSType? = nil) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: eventID,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        if let reason {
            event.setParam(NSAppleEventDescriptor(enumCode: reason), forKeyword: AEKeyword(kAEQuitReason))
        }
        return event
    }

    @Test func aQuitFromLinkdIsRefused() {
        #expect(AppIntentsIdleQuit.refuses(Self.event(kAEQuitApplication), isSentByLinkd: { _ in true }))
    }

    @Test func aQuitFromAnotherAppGoesAhead() {
        #expect(!AppIntentsIdleQuit.refuses(Self.event(kAEQuitApplication), isSentByLinkd: { _ in false }))
    }

    @Test(arguments: [kAELogOut, kAEReallyLogOut, kAERestart, kAEShutDown])
    func aQuitWithAReasonGoesAhead(reason: OSType) {
        #expect(!AppIntentsIdleQuit.refuses(Self.event(kAEQuitApplication, reason: reason), isSentByLinkd: { _ in true }))
    }

    @Test func anotherEventFromLinkdIsNotAQuit() {
        #expect(!AppIntentsIdleQuit.refuses(Self.event(kAEReopenApplication), isSentByLinkd: { _ in true }))
    }

    @Test func anEventWithoutASenderIsNotFromLinkd() {
        #expect(!AppIntentsIdleQuit.isSentByLinkd(Self.event(kAEQuitApplication)))
    }

    @Test func anotherProcessDoesNotPassForLinkd() {
        #expect(!AppIntentsIdleQuit.isLinkd(guestAttributes: [kSecGuestAttributePid: NSNumber(value: getpid())]))
    }

    @Test(arguments: [("/usr/libexec/linkd", true), ("/usr/bin/true", false)])
    func theRequirementMatchesOnlyLinkd(path: String, matches: Bool) throws {
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        try #require(SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess)
        try #require(SecRequirementCreateWithString(AppIntentsIdleQuit.linkdRequirement as CFString, [], &requirement) == errSecSuccess)
        let code = try #require(staticCode)
        #expect((SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess) == matches)
    }

    /// Outside a quit event, as in a test, there is nothing to refuse.
    @MainActor
    @Test func nothingIsRefusedOutsideAnEvent() {
        #expect(!AppIntentsIdleQuit.refusesCurrentRequest())
    }
}
