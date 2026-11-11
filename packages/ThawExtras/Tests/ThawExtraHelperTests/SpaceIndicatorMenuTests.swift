//
//  SpaceIndicatorMenuTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import ThawExtraHelper

@Suite("Space indicator menu")
struct SpaceIndicatorMenuTests {
    private let twoDisplays = SpaceIndicatorSnapshot(title: "Desktop 2", displays: [
        .init(name: "Studio Display", hasMenuBar: true, spaces: [
            .init(label: "Desktop 1", isCurrent: false),
            .init(label: "Desktop 2", isCurrent: true),
        ]),
        .init(name: "Built-in Display", hasMenuBar: false, spaces: [.init(label: "Desktop 1", isCurrent: true)]),
    ])

    @Test("Each display gets a heading, the menu bar's display says so, and current Spaces are checked")
    func twoDisplaysHaveHeadings() {
        #expect(SpaceIndicatorMenu.entries(for: twoDisplays) == [
            .header("Studio Display (menu bar)"),
            .space("Desktop 1", isCurrent: false),
            .space("Desktop 2", isCurrent: true),
            .header("Built-in Display"),
            .space("Desktop 1", isCurrent: true),
            .separator,
            .missionControl,
        ])
    }

    @Test("One display needs no heading")
    func oneDisplayHasNone() {
        let snapshot = SpaceIndicatorSnapshot(title: "Safari", displays: [
            .init(name: "Built-in Display", hasMenuBar: true, spaces: [.init(label: "Safari", isCurrent: true)]),
        ])
        #expect(SpaceIndicatorMenu.entries(for: snapshot) == [.space("Safari", isCurrent: true), .separator, .missionControl])
    }

    @Test("Before Thaw sends a snapshot the menu only opens Mission Control")
    func noSnapshot() {
        #expect(SpaceIndicatorMenu.entries(for: nil) == [.missionControl])
        #expect(SpaceIndicatorMenu.title(for: nil) == "Space")
        #expect(SpaceIndicatorMenu.title(for: twoDisplays) == "Desktop 2")
    }

    @Test("The helper reads the file Thaw writes, and a damaged file reads as none")
    func readsTheFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SpaceIndicatorMenuTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = SpaceIndicatorChannel.file(in: folder)

        #expect(SpaceIndicatorChannel.read(from: file) == nil)

        try JSONEncoder().encode(twoDisplays).write(to: file)
        #expect(SpaceIndicatorChannel.read(from: file) == twoDisplays)

        try Data("not json".utf8).write(to: file)
        #expect(SpaceIndicatorChannel.read(from: file) == nil)
    }

    @Test("The channel names match Thaw's")
    func channelNames() {
        #expect(SpaceIndicatorChannel.file(in: URL(filePath: "/x")).path == "/x/space.json")
        #expect(SpaceIndicatorChannel.notification(parent: "com.example").rawValue == "com.example.extra.space.update")
    }

    @Test("The Space role has its own permanent autosave name")
    func role() {
        #expect(ExtraRole(bundleIdentifier: "com.example.extra.space") == .space)
        #expect(ExtraRole.space.autosaveName == "Thaw.Extra.Space")
        #expect(ExtraRole.space.slot == nil)
    }
}
