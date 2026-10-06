//
//  DisplayTopologyChangeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing

@Suite("Display topology change")
struct DisplayTopologyChangeTests {
    private static let builtIn = DisplayTopologySnapshot.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117))
    private static let external = DisplayTopologySnapshot.Display(id: 5, frame: CGRect(x: 56, y: -1080, width: 1920, height: 1080))
    private static let other = DisplayTopologySnapshot.Display(id: 7, frame: CGRect(x: 56, y: -1080, width: 1920, height: 1080))

    private func snapshot(_ displays: [DisplayTopologySnapshot.Display], active: CGDirectDisplayID?) -> DisplayTopologySnapshot {
        DisplayTopologySnapshot(displays: displays, activeDisplayID: active)
    }

    @Test("Connecting and disconnecting are told apart")
    func connectAndDisconnect() {
        let one = snapshot([Self.builtIn], active: 1)
        let two = snapshot([Self.builtIn, Self.external], active: 1)
        #expect(DisplayTopologyChange.between(one, two) == .connected)
        #expect(DisplayTopologyChange.between(two, one) == .disconnected)
    }

    @Test("Swapping one display for another is both, not nothing")
    func swapIsBoth() {
        let before = snapshot([Self.builtIn, Self.external], active: 5)
        let after = snapshot([Self.builtIn, Self.other], active: 7)
        #expect(DisplayTopologyChange.between(before, after) == [.connected, .disconnected, .activeBarMoved])
    }

    @Test("A resized display is rearranged")
    func rearranged() {
        var resized = Self.builtIn
        resized.frame.size = CGSize(width: 1512, height: 982)
        let change = DisplayTopologyChange.between(snapshot([Self.builtIn], active: 1), snapshot([resized], active: 1))
        #expect(change == .rearranged)
    }

    @Test("The active bar moving counts only once it lands on a display")
    func activeBarMoved() {
        let displays = [Self.builtIn, Self.external]
        #expect(DisplayTopologyChange.between(snapshot(displays, active: 1), snapshot(displays, active: 5)) == .activeBarMoved)
        #expect(DisplayTopologyChange.between(snapshot(displays, active: 1), snapshot(displays, active: nil)).isEmpty)
        #expect(DisplayTopologyChange.between(snapshot(displays, active: 1), snapshot(displays, active: 1)).isEmpty)
    }
}
