//
//  BentoBoxModuleKeyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import MenuBarModel

@Suite("Control Center modules pinned to the menu bar resolve to their module row")
struct BentoBoxModuleKeyTests {
    // The agent sorts a pinned module under module:BentoBox-N; a write to any other key moves nothing.
    @Test(arguments: [1, 2, 7])
    func pinnedModuleResolvesToItsModuleRow(index: Int) {
        let title = "com.apple.menuextra.controlcenter-BentoBox-\(index)"
        #expect(SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: title) == "module:BentoBox-\(index)")
    }

    @Test func barePinnedModuleTitleKeepsItsName() {
        #expect(SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: "BentoBox-3") == "module:BentoBox-3")
    }

    @Test func controlCenterItselfIsUnchanged() {
        #expect(SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: "BentoBox-0") == "module:ControlCenter")
    }

    @Test func unrelatedTitleIsUnchanged() {
        #expect(SystemMenuBarModuleCatalog.trailingPositionsModuleKey(forTitle: "Something-Else") == "module:Something-Else")
    }
}
