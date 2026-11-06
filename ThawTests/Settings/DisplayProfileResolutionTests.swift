//
//  DisplayProfileResolutionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// Which profile a settled display change asks for.
@Suite("Display profile resolution")
struct DisplayProfileResolutionTests {
    private static let docked = ProfileMetadata(id: UUID(), name: "Docked", createdAt: .now, modifiedAt: .now, associatedDisplayUUID: "DOCK")
    private static let laptop = ProfileMetadata(id: UUID(), name: "Laptop", createdAt: .now, modifiedAt: .now, associatedDisplayUUID: "BUILTIN")
    private static let meetings = ProfileMetadata(id: UUID(), name: "Meetings", createdAt: .now, modifiedAt: .now, associatedSpaceKey: "space-2")
    private static let profiles = [docked, laptop, meetings]

    struct Row: CustomTestStringConvertible, Sendable {
        let name: String
        let situation: DisplayProfileResolution.Situation
        let expected: UUID?

        var testDescription: String {
            name
        }
    }

    static let rows: [Row] = [
        Row(
            name: "The new display's profile applies",
            situation: .init(displayUUID: "DOCK", previousDisplayUUID: "BUILTIN", activeProfileID: laptop.id),
            expected: docked.id
        ),
        Row(
            name: "The display's profile applies when none is active",
            situation: .init(displayUUID: "DOCK", previousDisplayUUID: "BUILTIN"),
            expected: docked.id
        ),
        Row(
            name: "A display no profile names switches nothing",
            situation: .init(displayUUID: "PROJECTOR", previousDisplayUUID: "BUILTIN", activeProfileID: laptop.id),
            expected: nil
        ),
        Row(
            name: "A Focus filter's profile wins",
            situation: .init(displayUUID: "DOCK", previousDisplayUUID: "BUILTIN", focusFilterActive: true, activeProfileID: laptop.id),
            expected: nil
        ),
        Row(
            name: "A Space's own profile wins",
            situation: .init(displayUUID: "DOCK", previousDisplayUUID: "BUILTIN", activeSpaceKey: "space-2", activeProfileID: meetings.id),
            expected: nil
        ),
        Row(
            name: "A Space no profile names leaves the display's profile to apply",
            situation: .init(displayUUID: "DOCK", previousDisplayUUID: "BUILTIN", activeSpaceKey: "space-9", activeProfileID: laptop.id),
            expected: docked.id
        ),
        Row(
            name: "The display's profile already active switches nothing",
            situation: .init(displayUUID: "DOCK", previousDisplayUUID: "BUILTIN", activeProfileID: docked.id),
            expected: nil
        ),
        Row(
            name: "A change that leaves the bar on the same display keeps a profile picked by hand",
            situation: .init(displayUUID: "DOCK", previousDisplayUUID: "DOCK", activeProfileID: laptop.id),
            expected: nil
        ),
        Row(
            name: "No display owning the bar switches nothing",
            situation: .init(displayUUID: nil, previousDisplayUUID: "BUILTIN", activeProfileID: laptop.id),
            expected: nil
        ),
    ]

    @Test(arguments: rows)
    func resolves(_ row: Row) {
        #expect(DisplayProfileResolution.resolve(row.situation, profiles: Self.profiles) == row.expected)
    }

    @Test("No profiles, nothing to apply")
    func noProfiles() {
        #expect(DisplayProfileResolution.resolve(.init(displayUUID: "DOCK", previousDisplayUUID: "BUILTIN"), profiles: []) == nil)
    }
}
