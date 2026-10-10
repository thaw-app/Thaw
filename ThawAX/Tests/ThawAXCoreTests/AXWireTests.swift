//
//  AXWireTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawAXCore

struct AXWireTests {
    @Test
    func `request round-trips through framing`() throws {
        let request = AXEnumerateRequest(displayID: 1, deadlineSeconds: 2.5)
        let pipe = Pipe()
        try AXWire.write(request, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()

        let decoded = try AXWire.read(AXEnumerateRequest.self, from: pipe.fileHandleForReading)
        #expect(decoded == request)
    }

    @Test
    func `reply round-trips observations`() throws {
        let observed = AXItemObservation(
            bundleID: "com.example.app",
            processName: "Example",
            ownerPID: 42,
            identifier: "Example.StatusItem",
            accessibilityDescription: nil,
            title: "Example",
            help: nil,
            frame: CGRect(x: 10, y: 0, width: 24, height: 24),
            isOverflowControl: false
        )
        let reply = AXEnumerateReply(
            items: [observed],
            completed: true,
            accessibilityTrusted: true
        )
        let pipe = Pipe()
        try AXWire.write(reply, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()

        let decoded = try AXWire.read(AXEnumerateReply.self, from: pipe.fileHandleForReading)
        #expect(decoded == reply)
    }

    @Test
    func `every helper request round-trips through framing`() throws {
        let requests: [AXHelperRequest] = [
            .enumerate(AXEnumerateRequest(displayID: 2)),
            .applicationMenuFrames(pid: 42),
            .hitTest(x: 120.5, y: 12),
            .pressStatusItem(pid: 42, targetX: 300, targetY: 11, tolerance: 10),
            .pressHostedItem(sourcePID: 77),
        ]
        for request in requests {
            let pipe = Pipe()
            try AXWire.write(request, to: pipe.fileHandleForWriting)
            try pipe.fileHandleForWriting.close()
            let decoded = try AXWire.read(AXHelperRequest.self, from: pipe.fileHandleForReading)
            #expect(decoded == request)
        }
    }

    @Test
    func `request round-trips the maximum item height`() throws {
        let request = AXEnumerateRequest(displayID: 1, deadlineSeconds: 2.5, maximumItemHeight: 47.5)
        let pipe = Pipe()
        try AXWire.write(request, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()

        let decoded = try AXWire.read(AXEnumerateRequest.self, from: pipe.fileHandleForReading)
        #expect(decoded == request)
        #expect(decoded?.maximumItemHeight == 47.5)
    }

    @Test
    func `reply round-trips the child identity fields`() throws {
        let observed = AXItemObservation(
            bundleID: "com.example.app",
            processName: "Example",
            ownerPID: 42,
            identifier: nil,
            accessibilityDescription: nil,
            title: nil,
            help: nil,
            frame: CGRect(x: 10, y: 0, width: 24, height: 24),
            isOverflowControl: false,
            childIdentifier: "Example.Nested",
            childDescription: "Nested"
        )
        let reply = AXEnumerateReply(items: [observed], completed: true, accessibilityTrusted: true)
        let pipe = Pipe()
        try AXWire.write(reply, to: pipe.fileHandleForWriting)
        try pipe.fileHandleForWriting.close()

        let decoded = try AXWire.read(AXEnumerateReply.self, from: pipe.fileHandleForReading)
        #expect(decoded == reply)
        #expect(decoded?.items.first?.childIdentifier == "Example.Nested")
        #expect(decoded?.items.first?.childDescription == "Nested")
    }

    @Test
    func `a request without the maximum height field still decodes`() throws {
        let request = AXEnumerateRequest(displayID: 3, deadlineSeconds: 1, maximumItemHeight: 55)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        object.removeValue(forKey: "maximumItemHeight")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AXEnumerateRequest.self, from: data)
        #expect(decoded == AXEnumerateRequest(displayID: 3, deadlineSeconds: 1))
        #expect(decoded.maximumItemHeight == nil)
    }

    @Test
    func `an observation without the child fields still decodes`() throws {
        let observed = AXItemObservation(
            bundleID: "com.example.app",
            processName: "Example",
            ownerPID: 42,
            identifier: "Example",
            accessibilityDescription: nil,
            title: "Example",
            help: nil,
            frame: CGRect(x: 10, y: 0, width: 24, height: 24),
            isOverflowControl: false,
            childIdentifier: "Example.Nested",
            childDescription: "Nested"
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(observed)) as? [String: Any]
        )
        object.removeValue(forKey: "childIdentifier")
        object.removeValue(forKey: "childDescription")
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AXItemObservation.self, from: data)
        #expect(decoded.childIdentifier == nil)
        #expect(decoded.childDescription == nil)
        #expect(decoded.identifier == "Example")
    }

    @Test
    func `helper replies keep unreadable apart from empty`() throws {
        let replies: [AXHelperReply] = [
            .applicationMenuFrames(frames: nil, accessibilityTrusted: true),
            .applicationMenuFrames(frames: [], accessibilityTrusted: true),
            .applicationMenuFrames(frames: [CGRect(x: 0, y: 0, width: 40, height: 24)], accessibilityTrusted: true),
            .hitTest(AXHitTestResult(pid: 9, role: "AXMenuBarItem"), accessibilityTrusted: true),
            .hitTest(nil, accessibilityTrusted: false),
            .press(pressed: true, accessibilityTrusted: true),
        ]
        for reply in replies {
            let pipe = Pipe()
            try AXWire.write(reply, to: pipe.fileHandleForWriting)
            try pipe.fileHandleForWriting.close()
            let decoded = try AXWire.read(AXHelperReply.self, from: pipe.fileHandleForReading)
            #expect(decoded == reply)
        }
        #expect(AXHelperReply.hitTest(nil, accessibilityTrusted: false).accessibilityTrusted == false)
    }

    @Test
    func `tagged frames round-trip, superseded included`() throws {
        let request = AXRequestFrame(id: 7, request: .hitTest(x: 10, y: 5))
        let replies = [
            AXReplyFrame(id: 7, outcome: .superseded),
            AXReplyFrame(id: 8, outcome: .reply(.press(pressed: true, accessibilityTrusted: true))),
        ]
        let pipe = Pipe()
        try AXWire.write(request, to: pipe.fileHandleForWriting)
        for reply in replies {
            try AXWire.write(reply, to: pipe.fileHandleForWriting)
        }
        try pipe.fileHandleForWriting.close()
        #expect(try AXWire.read(AXRequestFrame.self, from: pipe.fileHandleForReading) == request)
        for reply in replies {
            #expect(try AXWire.read(AXReplyFrame.self, from: pipe.fileHandleForReading) == reply)
        }
    }

    @Test
    func `every request kind has the lane its policy expects`() {
        #expect(AXHelperRequest.enumerate(AXEnumerateRequest()).lane == .walk)
        #expect(AXHelperRequest.applicationMenuFrames(pid: 1).lane == .menu)
        #expect(AXHelperRequest.hitTest(x: 0, y: 0).lane == .pointer)
        #expect(AXHelperRequest.pressStatusItem(pid: 1, targetX: 0, targetY: 0, tolerance: 10).lane == .press)
        #expect(AXHelperRequest.pressHostedItem(sourcePID: 1).lane == .press)
    }

    @Test
    func `end of stream returns nil`() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.close()
        let decoded = try AXWire.read(AXEnumerateRequest.self, from: pipe.fileHandleForReading)
        #expect(decoded == nil)
    }

    @Test
    func `a silent stream times out instead of blocking`() {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForWriting.close() }
        #expect(throws: AXWire.WireError.timedOut) {
            _ = try AXWire.read(AXEnumerateRequest.self, from: pipe.fileHandleForReading, timeoutSeconds: 0.2)
        }
    }
}
