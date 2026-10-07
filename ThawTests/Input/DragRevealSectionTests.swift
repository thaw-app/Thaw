//
//  DragRevealSectionTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
@Suite("A ⌘-drag opens the deepest section there is")
struct DragRevealSectionTests {
    @Test func opensAlwaysHiddenWhenItIsEnabled() {
        #expect(HIDEventManager.sectionRevealedForDrag(enabled: [.visible, .hidden, .alwaysHidden]) == .alwaysHidden)
    }

    @Test func opensHiddenWhenAlwaysHiddenIsOff() {
        #expect(HIDEventManager.sectionRevealedForDrag(enabled: [.visible, .hidden]) == .hidden)
    }

    @Test func opensNothingWhenOnlyVisibleExists() {
        #expect(HIDEventManager.sectionRevealedForDrag(enabled: [.visible]) == nil)
    }
}
