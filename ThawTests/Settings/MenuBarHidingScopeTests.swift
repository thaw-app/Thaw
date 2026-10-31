//
//  MenuBarHidingScopeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Displays shows the two menu bar hiding overrides as one picker. These pin
/// how the picker reads them and which overrides each choice asks for.
@Suite("Menu bar hiding scope")
struct MenuBarHidingScopeTests {
    @Test("The picker reads the two overrides, every Space first", arguments: [
        (false, false, MenuBarHidingScope.never),
        (true, false, .thisSpace),
        (false, true, .everySpace),
        (true, true, .everySpace),
    ])
    func readsTheOverrides(inSpace: Bool, everywhere: Bool, expected: MenuBarHidingScope) {
        #expect(MenuBarHidingScope(hiddenInSpace: inSpace, hiddenEverywhere: everywhere) == expected)
    }

    @Test("Only the overrides that change are sent")
    func sendsOnlyChanges() {
        #expect(MenuBarHidingScope.never.requests(fromHiddenInSpace: false, hiddenEverywhere: false).isEmpty)
        #expect(MenuBarHidingScope.thisSpace.requests(fromHiddenInSpace: false, hiddenEverywhere: false) == [.thisSpace(hidden: true)])
        #expect(MenuBarHidingScope.never.requests(fromHiddenInSpace: false, hiddenEverywhere: true) == [.everySpace(hidden: false)])
    }

    @Test("Moving between the two hides first, so the bar doesn't flash back", arguments: [
        (MenuBarHidingScope.thisSpace, false, true, [MenuBarHidingScope.Request.thisSpace(hidden: true), .everySpace(hidden: false)]),
        (MenuBarHidingScope.everySpace, true, false, [MenuBarHidingScope.Request.everySpace(hidden: true), .thisSpace(hidden: false)]),
    ])
    func hidesBeforeShowing(
        scope: MenuBarHidingScope,
        inSpace: Bool,
        everywhere: Bool,
        expected: [MenuBarHidingScope.Request]
    ) {
        #expect(scope.requests(fromHiddenInSpace: inSpace, hiddenEverywhere: everywhere) == expected)
    }
}
