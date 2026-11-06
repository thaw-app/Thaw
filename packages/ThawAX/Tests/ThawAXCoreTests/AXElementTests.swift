//
//  AXElementTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import ApplicationServices
import CoreGraphics
import Testing
@testable import ThawAXCore

struct AXElementTests {
    @Test
    func `two wraps of one element are equal and hash alike`() {
        let first = AXElement.application(getpid())
        let second = AXElement.application(getpid())
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != AXElement.application(getppid()))
    }

    @Test
    func `geometry values unpack to their Swift types`() throws {
        var rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let value = try #require(AXValueCreate(.cgRect, &rect))
        #expect(AXElement.unpack(value) as? CGRect == rect)
    }

    @Test
    func `an error placeholder unpacks to nil`() throws {
        var error = AXError.attributeUnsupported
        let value = try #require(AXValueCreate(.axError, &error))
        #expect(AXElement.unpack(value) == nil)
    }

    @Test
    func `arrays unpack per element and wrap elements`() {
        let raw = AXUIElementCreateApplication(getpid())
        let array: CFArray = [raw, "title" as CFString] as CFArray
        let unpacked = AXElement.unpack(array) as? [Any]
        #expect(unpacked?.count == 2)
        #expect(unpacked?.first as? AXElement == AXElement(raw))
        #expect(unpacked?.last as? String == "title")
    }

    @Test
    func `a batch reply that is not an array is refused, not bridged`() {
        // The reply behind a crash in the item walk: success, with an element where the array should be.
        let malformed = unsafeBitCast(AXUIElementCreateApplication(getpid()), to: CFArray.self)
        #expect(AXElement.batchValues(malformed, expecting: 1) == nil)
        #expect(AXElement.batchValues(nil, expecting: 1) == nil)
    }

    @Test
    func `a batch reply holds one value per attribute`() {
        let reply = ["a", "b"] as CFArray
        #expect(AXElement.batchValues(reply, expecting: 2)?.count == 2)
        #expect(AXElement.batchValues(reply, expecting: 3) == nil)
    }

    @Test
    func `a negative default timeout clamps to the system default`() {
        let saved = AXElement.defaultMessagingTimeout
        defer { AXElement.defaultMessagingTimeout = saved }
        AXElement.defaultMessagingTimeout = -1
        #expect(AXElement.defaultMessagingTimeout == 0)
    }

    @Test
    func `an element with no position answers nil, not a zero point`() {
        #expect(AXPrimitives.position(of: AXUIElementCreateApplication(getpid())) == nil)
    }

    @Test
    func `a process with no extras bar reports why, not success`() {
        #expect(AXPrimitives.extrasMenuBarReadResult(pid: getpid()) != .success)
    }
}
