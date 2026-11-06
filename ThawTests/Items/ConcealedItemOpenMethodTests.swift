//
//  ConcealedItemOpenMethodTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Pins the order ConcealedItemOpenMethod.openAttempts(for:learned:showInMenuBar:) tries
/// the ways of opening a concealed item.
@MainActor
struct ConcealedItemOpenMethodTests {
    @Test("with nothing learned, a left click climbs from the press to the real click")
    func defaultLeftOrder() {
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .left, learned: nil)
                == [[.pressInPlace], [.revealAndPress, .revealAndClick]]
        )
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .left, learned: .pressInPlace)
                == [[.pressInPlace], [.revealAndPress, .revealAndClick]]
        )
    }

    @Test("a learned reveal and press goes first and never falls through to the real click")
    func learnedRevealAndPressNeverClicks() {
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .left, learned: .revealAndPress)
                == [[.revealAndPress], [.pressInPlace]]
        )
    }

    @Test("a learned real click goes straight to it, skipping both presses' waits")
    func learnedRealClickSkipsPresses() {
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .left, learned: .revealAndClick)
                == [[.revealAndClick], [.pressInPlace]]
        )
    }

    @Test("an item learned as reveal in place, before the real click split off, isn't read as reveal and press")
    func oldRevealInPlaceIsNotRead() {
        #expect(ConcealedItemOpenMethod(rawValue: "revealInPlace") == nil)
    }

    @Test("a right click opens its menu in place first and never tries a press")
    func rightClickSkipsPress() {
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .right, learned: nil)
                == [[.showMenuInPlace], [.revealAndClick]]
        )
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .right, learned: .pressInPlace)
                == [[.showMenuInPlace], [.revealAndClick]]
        )
    }

    @Test("a right click's method is never tried first on a left click")
    func leftClickIgnoresLearnedShowMenu() {
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .left, learned: .showMenuInPlace)
                == [[.pressInPlace], [.revealAndPress, .revealAndClick]]
        )
    }

    @Test("showing items in the menu bar reveals first and keeps the press as a fallback")
    func showInMenuBarRevealsFirst() {
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .left, learned: nil, showInMenuBar: true)
                == [[.revealAndPress, .revealAndClick], [.pressInPlace]]
        )
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .left, learned: .revealAndClick, showInMenuBar: true)
                == [[.revealAndClick], [.pressInPlace]]
        )
        #expect(
            ConcealedItemOpenMethod.openAttempts(for: .right, learned: nil, showInMenuBar: true)
                == [[.revealAndClick]]
        )
    }
}
