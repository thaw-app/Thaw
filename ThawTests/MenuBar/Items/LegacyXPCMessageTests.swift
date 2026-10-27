//
//  LegacyXPCMessageTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw
import XPC

@Suite("Legacy XPC messages")
struct LegacyXPCMessageTests {
    @Test("A capture request survives the payload round trip")
    func requestRoundTrip() throws {
        let request = MenuBarCaptureService.Request.captureBatch(
            MenuBarCaptureService.CaptureBatchRequest(
                requestID: 42,
                windowIDs: [100, 200],
                optionRawValue: 3,
                expectedScale: 2
            )
        )
        let dictionary = xpc_dictionary_create(nil, nil, 0)

        try LegacyXPCMessage.setPayload(request, in: dictionary)
        let data = try #require(LegacyXPCMessage.payload(in: dictionary))

        #expect(try LegacyXPCMessage.decode(MenuBarCaptureService.Request.self, from: data) == request)
    }

    @Test("A capture response keeps its pixel bytes")
    func responseRoundTrip() throws {
        let frame = MenuBarCaptureService.Frame(
            windowID: 7,
            width: 2,
            height: 1,
            bytesPerRow: 8,
            scale: 2,
            pixels: Data([0, 1, 2, 3, 4, 5, 6, 7])
        )
        let response = MenuBarCaptureService.Response.captureBatch(
            MenuBarCaptureService.CaptureBatchResponse(requestID: 42, instanceID: 9, frames: [frame])
        )
        let dictionary = xpc_dictionary_create(nil, nil, 0)

        try LegacyXPCMessage.setPayload(response, in: dictionary)
        let data = try #require(LegacyXPCMessage.payload(in: dictionary))

        #expect(try LegacyXPCMessage.decode(MenuBarCaptureService.Response.self, from: data) == response)
    }

    @Test("An empty reply or a non-dictionary has no payload")
    func missingPayload() {
        #expect(LegacyXPCMessage.payload(in: xpc_dictionary_create(nil, nil, 0)) == nil)
        #expect(LegacyXPCMessage.payload(in: xpc_string_create("payload")) == nil)
    }

    @Test("The same-team requirement names the team's certificate")
    func sameTeamRequirement() {
        #expect(
            LegacyXPCMessage.sameTeamRequirement(teamIdentifier: "AB12CD34EF")
                == "anchor apple generic and certificate leaf[subject.OU] = \"AB12CD34EF\""
        )
    }

    @Test("Anything but a ten-character team ID gets no requirement", arguments: [
        "", "AB12CD34E", "AB12CD34EFG", "ab12cd34ef", "AB12CD34E\"", "AB12 CD34E",
    ])
    func malformedTeamIdentifier(_ teamIdentifier: String) {
        #expect(LegacyXPCMessage.sameTeamRequirement(teamIdentifier: teamIdentifier) == nil)
    }

    @Test("A connection without a team keeps no requirement")
    func noTeamAppliesNothing() {
        let connection = xpc_connection_create(nil, nil)
        defer { LegacyXPCMessage.discard(connection) }

        #expect(LegacyXPCMessage.applySameTeamRequirement(to: connection, teamIdentifier: nil))
    }

    @Test("A malformed team refuses the connection")
    func malformedTeamRefuses() {
        let connection = xpc_connection_create(nil, nil)
        defer { LegacyXPCMessage.discard(connection) }

        #expect(!LegacyXPCMessage.applySameTeamRequirement(to: connection, teamIdentifier: "bad"))
    }

    @Test("A valid team requirement applies to a connection")
    func validTeamApplies() {
        let connection = xpc_connection_create(nil, nil)
        defer { LegacyXPCMessage.discard(connection) }

        #expect(LegacyXPCMessage.applySameTeamRequirement(to: connection, teamIdentifier: "AB12CD34EF"))
    }
}
