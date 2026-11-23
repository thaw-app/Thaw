//
//  LazyPanelLifecycleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Lazy panel creation", .serialized, .scratchDefaults)
struct LazyPanelLifecycleTests {
    @Test("MenuBarManager leaves floating panels unallocated until first access")
    func panelsRemainNilUntilAccessed() {
        let manager = MenuBarManager()
        #expect(manager.thawBarPanelIfCreated == nil)
        #expect(manager.searchPanelIfCreated == nil)
        #expect(manager.appearanceEditorPanelIfCreated == nil)
        #expect(manager.layoutEditorPanelIfCreated == nil)

        _ = manager.thawBarPanel
        _ = manager.searchPanel
        _ = manager.appearanceEditorPanel
        _ = manager.layoutEditorPanel

        #expect(manager.thawBarPanelIfCreated != nil)
        #expect(manager.searchPanelIfCreated != nil)
        #expect(manager.appearanceEditorPanelIfCreated != nil)
        #expect(manager.layoutEditorPanelIfCreated != nil)
    }
}
