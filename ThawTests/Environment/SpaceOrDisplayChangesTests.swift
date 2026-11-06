//
//  SpaceOrDisplayChangesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import Testing
@testable import Thaw

@MainActor
@Suite("Space or display changes")
struct SpaceOrDisplayChangesTests {
    @Test("A Space change and a display change each send once, in the posting turn")
    func sendsForBoth() {
        let center = NotificationCenter()
        let display = PassthroughSubject<Void, Never>()
        var sends = 0
        let cancellable = DisplayEnvironment.spaceOrDisplayChanges(merging: display, center: center)
            .sink { sends += 1 }
        defer { cancellable.cancel() }

        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        #expect(sends == 1)
        display.send()
        #expect(sends == 2)
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(sends == 2, "Only the display publisher stands for display changes")
    }
}
