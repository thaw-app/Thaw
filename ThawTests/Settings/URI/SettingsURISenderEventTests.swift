//
//  SettingsURISenderEventTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Settings URI sender from Apple events")
struct SettingsURISenderEventTests {
    private func makeEvent() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    private func ownAuditToken() -> Data? {
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &token) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        return withUnsafeBytes(of: &token) { Data($0) }
    }

    private var ownIdentity: SettingsURISender? {
        SettingsURISender.identify(pid: ProcessInfo.processInfo.processIdentifier)
    }

    @Test("A process is identified from its audit token")
    func auditToken() throws {
        let token = try #require(ownAuditToken())

        #expect(SettingsURISender.identify(auditToken: token) == ownIdentity)
        #expect(SettingsURISender.identify(auditToken: Data(count: 32)) == nil)
    }

    @Test("A PID is read from any integer descriptor", arguments: [DescType(typeSInt32), DescType(typeUInt32)])
    func senderPID(_ type: DescType) throws {
        var pid: pid_t = 4242
        let descriptor = try #require(NSAppleEventDescriptor(descriptorType: type, bytes: &pid, length: MemoryLayout<pid_t>.size))

        #expect(SettingsURISender.pid(from: descriptor) == 4242)
    }

    @Test("A PID in another descriptor type is coerced")
    func coercedPID() {
        #expect(SettingsURISender.pid(from: NSAppleEventDescriptor(int32: 4242)) == 4242)
        #expect(SettingsURISender.pid(from: NSAppleEventDescriptor(string: "4242")) == 4242)
    }

    @Test("A zero or negative PID is no PID, and an event without sender attributes has no sender")
    func noSender() throws {
        var zero: pid_t = 0
        let descriptor = try #require(NSAppleEventDescriptor(descriptorType: DescType(typeSInt32), bytes: &zero, length: MemoryLayout<pid_t>.size))

        #expect(SettingsURISender.pid(from: descriptor) == nil)
        #expect(SettingsURISender.identify(from: makeEvent()) == nil)
    }
}
