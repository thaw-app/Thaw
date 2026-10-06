//
//  DisplayTopologyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("Display topology fan-in")
struct DisplayTopologyTests {
    private static let builtIn = DisplayTopologySnapshot.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117))
    private static let external = DisplayTopologySnapshot.Display(id: 5, frame: CGRect(x: 56, y: -1080, width: 1920, height: 1080))

    /// A scripted snapshot source the test can change between notifications.
    @MainActor
    private final class Displays {
        var current = DisplayTopologySnapshot(displays: [DisplayTopologyTests.builtIn], activeDisplayID: 1)
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A burst of notifications settles into one event that runs every reaction in order")
    func burstRunsReactionsOnceInOrder() async {
        let displays = Displays()
        let topology = DisplayTopology(settleInterval: .milliseconds(50)) { displays.current }
        var log = [String]()
        topology.start(reactions: [
            { event in
                log.append("caches \(event.generation)")
                // A slow first reaction must finish before the second starts.
                try? await Task.sleep(for: .milliseconds(30))
                log.append("caches done")
            },
            { event in log.append("rescan \(event.change == .connected)") },
        ])

        displays.current = DisplayTopologySnapshot(displays: [Self.builtIn, Self.external], activeDisplayID: 1)
        for _ in 0 ..< 4 {
            topology.noteScreenParametersChanged()
        }
        await Self.waitUntil { log.count == 3 }

        #expect(log == ["caches 1", "caches done", "rescan true"])
        #expect(topology.generation == 1)
        #expect(topology.snapshot.displays.count == 2)
    }

    @Test("Events never overlap: a second burst waits for the first one's reactions")
    func eventsAreSerialized() async {
        let displays = Displays()
        let topology = DisplayTopology(settleInterval: .milliseconds(20)) { displays.current }
        var log = [String]()
        topology.start(reactions: [
            { event in
                log.append("start \(event.generation)")
                try? await Task.sleep(for: .milliseconds(80))
                log.append("end \(event.generation)")
            },
        ])

        displays.current.displays.append(Self.external)
        topology.noteScreenParametersChanged()
        try? await Task.sleep(for: .milliseconds(40))
        displays.current.displays.removeLast()
        topology.noteScreenParametersChanged()
        await Self.waitUntil { log.count == 4 }

        #expect(log == ["start 1", "end 1", "start 2", "end 2"])
    }
}
