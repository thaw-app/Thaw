//
//  SettingsURISenderSignatureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Security
import Testing
@testable import Thaw

/// How a thaw:// sender's PID is read from an Apple Event, and what a real signature on this Mac yields.
/// Only Apple's own code is read, so the expectations hold on every Mac.
@Suite("Settings URI sender signatures")
struct SettingsURISenderSignatureTests {
    private func descriptor<Value>(_ type: DescType, _ value: Value) -> NSAppleEventDescriptor? {
        var value = value
        return withUnsafeBytes(of: &value) { bytes in
            NSAppleEventDescriptor(descriptorType: type, bytes: bytes.baseAddress, length: bytes.count)
        }
    }

    @Test("A sender PID of any integer width is read as that PID")
    func everyIntegerWidthIsRead() throws {
        let descriptors = try [
            #require(descriptor(typeSInt16, Int16(77))),
            #require(descriptor(typeSInt32, Int32(4242))),
            #require(descriptor(typeUInt32, UInt32(4243))),
            #require(descriptor(typeSInt64, Int64(4244))),
            #require(descriptor(typeUInt64, UInt64(4245))),
        ]
        #expect(descriptors.map(SettingsURISender.pid(fromSenderDescriptor:)) == [77, 4242, 4243, 4244, 4245])
    }

    @Test("A sender PID that is zero or negative names no process")
    func nonPositivePIDIsNone() throws {
        #expect(SettingsURISender.pid(fromSenderDescriptor: NSAppleEventDescriptor(int32: 0)) == nil)
        #expect(SettingsURISender.pid(fromSenderDescriptor: NSAppleEventDescriptor(int32: -5)) == nil)
        let negative = try #require(descriptor(typeSInt64, Int64(-5)))
        #expect(SettingsURISender.pid(fromSenderDescriptor: negative) == nil)
    }

    @Test("A sender attribute that is not an integer is coerced, and one that can't be gives no PID")
    func nonIntegerIsCoerced() {
        #expect(SettingsURISender.pid(fromSenderDescriptor: NSAppleEventDescriptor(string: "123")) == 123)
        #expect(SettingsURISender.pid(fromSenderDescriptor: NSAppleEventDescriptor(string: "none")) == nil)
    }

    @Test("A running Apple process is named by its signing identifier and has no team")
    func runningProcessIsIdentified() throws {
        let sender = try #require(SettingsURISender.identify(guestAttributes: [kSecGuestAttributePid: NSNumber(value: 1)]))
        #expect(sender.bundleIdentifier == "com.apple.xpc.launchd")
        #expect(sender.teamIdentifier == nil)
        #expect(sender.codeHash?.count == 40, "launchd's code directory hash is a SHA-1 or truncated SHA-256 in hex")
    }

    @Test("A process that isn't running identifies nobody")
    func missingProcessIsAnonymous() {
        #expect(SettingsURISender.identify(guestAttributes: [kSecGuestAttributePid: NSNumber(value: Int32.max)]) == nil)
    }

    @Test("A picked Apple app is named by its signed Info.plist")
    func pickedAppIsIdentified() throws {
        let sender = try #require(SettingsURISender.identify(appAt: URL(fileURLWithPath: "/System/Applications/Calculator.app")))
        #expect(sender.bundleIdentifier == "com.apple.calculator")
        #expect(sender.teamIdentifier == nil)
        #expect(sender.displayName == "Calculator")
        #expect(SettingsURISender.identify(appAt: URL(fileURLWithPath: "/nonexistent/Thaw Test.app")) == nil)
    }

    @Test("Apple's own code is anchored to no developer team, and a malformed team is anchored to nothing")
    func appleCodeIsNotATeam() throws {
        var staticCode: SecStaticCode?
        let url = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        try #require(SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess)
        let code = try #require(staticCode)
        #expect(!SettingsURISender.isAnchored(code, toTeam: "ABCDE12345"))
        #expect(!SettingsURISender.isAnchored(code, toTeam: "not a team"))
    }
}
