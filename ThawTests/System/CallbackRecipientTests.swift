//
//  CallbackRecipientTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Which app a thaw:// response may be opened with: only the sender's own, by signature.
@Suite("Callback recipient")
struct CallbackRecipientTests {
    private let callback = URL(string: "thawctl://response")!
    private let handlerApp = URL(fileURLWithPath: "/Applications/ThawCtl.app")
    private let teamSender = SettingsURISender(bundleIdentifier: "com.example.ctl", teamIdentifier: "TEAM123456", codeHash: "aa")
    private let hashSender = SettingsURISender(bundleIdentifier: "com.example.ctl", teamIdentifier: nil, codeHash: "aa")

    private func recipient(for sender: SettingsURISender, handler: SettingsURISender?) -> URL? {
        CallbackRecipient.application(
            for: callback, sender: sender,
            handler: { _ in handlerApp }, identify: { _ in handler }
        )
    }

    @Test("The sender's own app, signed by its team, gets the response")
    func sameTeamIsAccepted() {
        let handler = SettingsURISender(bundleIdentifier: "COM.EXAMPLE.CTL", teamIdentifier: "TEAM123456", codeHash: "bb")
        #expect(recipient(for: teamSender, handler: handler) == handlerApp)
    }

    @Test("An app that only claims the sender's bundle ID gets nothing", arguments: [
        SettingsURISender(bundleIdentifier: "com.example.ctl", teamIdentifier: nil, codeHash: "aa"),
        SettingsURISender(bundleIdentifier: "com.example.ctl", teamIdentifier: "OTHER12345", codeHash: "aa"),
        SettingsURISender(bundleIdentifier: "com.example.other", teamIdentifier: "TEAM123456", codeHash: "aa"),
    ])
    func claimedIdentityIsRefused(handler: SettingsURISender) {
        #expect(recipient(for: teamSender, handler: handler) == nil)
    }

    @Test("A sender without a team is matched by its code hash")
    func teamlessSenderNeedsSameHash() {
        let same = SettingsURISender(bundleIdentifier: "com.example.ctl", teamIdentifier: nil, codeHash: "AA")
        let other = SettingsURISender(bundleIdentifier: "com.example.ctl", teamIdentifier: nil, codeHash: "cc")
        #expect(recipient(for: hashSender, handler: same) == handlerApp)
        #expect(recipient(for: hashSender, handler: other) == nil)
    }

    @Test("No handler, or one whose signature can't be read, gets nothing")
    func unknownHandlerIsRefused() {
        #expect(recipient(for: teamSender, handler: nil) == nil)
        #expect(CallbackRecipient.application(
            for: callback, sender: teamSender, handler: { _ in nil }, identify: { _ in teamSender }
        ) == nil)
    }

    private final class Launches {
        var opened: [(url: URL, app: URL?)] = []
    }

    private func open(answering sender: SettingsURISender?, handler: SettingsURISender?, launches: Launches) -> Bool {
        CallbackRecipient.open(
            callback, answering: sender,
            handler: { _ in handlerApp }, identify: { _ in handler },
            launch: { url, app in
                launches.opened.append((url, app))
                return true
            }
        )
    }

    @Test("A response is opened with the sender's own app once its signature is confirmed")
    func confirmedSenderGetsItsApp() {
        let launches = Launches()
        #expect(open(answering: teamSender, handler: teamSender, launches: launches))
        #expect(launches.opened.map(\.url) == [callback])
        #expect(launches.opened.map(\.app) == [handlerApp])
    }

    @Test("A response for an app whose signature doesn't match is not opened at all")
    func unconfirmedSenderOpensNothing() {
        let launches = Launches()
        let impostor = SettingsURISender(bundleIdentifier: "com.example.ctl", teamIdentifier: "OTHER12345", codeHash: "aa")
        #expect(!open(answering: teamSender, handler: impostor, launches: launches))
        #expect(launches.opened.isEmpty)
    }

    @Test("Without a sender to answer to, the response goes to whatever handles it")
    func anonymousResponseUsesTheDefaultHandler() {
        let launches = Launches()
        #expect(open(answering: nil, handler: nil, launches: launches))
        #expect(launches.opened.map(\.url) == [callback])
        #expect(launches.opened.map(\.app) == [nil])
    }

    @Test("The system's own handler lookup never confirms a sender that no installed app is")
    func systemLookupRefusesAnUnknownSender() throws {
        let stranger = SettingsURISender(bundleIdentifier: "com.example.thaw-test-none", teamIdentifier: "TEAM123456", codeHash: nil)
        let url = try #require(URL(string: "facetime:thaw-test"))
        #expect(CallbackRecipient.application(for: url, sender: stranger) == nil)
    }
}
