//
//  MenuBarScanScopeWalkLabelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

struct MenuBarScanScopeWalkLabelTests {
    @Test(arguments: [
        (MenuBarScanScope.discovery, "discovery"),
        (.settledOwners, "settled"),
        (.knownOwners, "targeted"),
        (.requestedOwners, "targeted"),
        (.itemOwners, "targeted"),
    ])
    func labelsEachScope(scope: MenuBarScanScope, label: String) {
        #expect(scope.walkLabel == label)
    }
}
