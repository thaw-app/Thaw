//
//  ClickGuardAndKeyTableTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw
import ThawUI

/// The show-on-click guard's swallow and disarm rules, without a live event tap.
@Suite("Show-on-click guard")
struct ShowOnClickGuardTests {
    @Test("A mouse-up always returns the guard to idle")
    func mouseUpResets() {
        for state in [HIDEventManager.GuardMouseUpState.idle, .swallowing, .swallowingThenDisarm] {
            #expect(HIDEventManager.nextGuardState(from: state, given: .mouseUp) == .idle)
        }
    }

    @Test("A swallowed mouse-down decides whether the guard disarms after its mouse-up")
    func swallowSignals() {
        #expect(HIDEventManager.nextGuardState(from: .idle, given: .swallow) == .swallowing)
        #expect(HIDEventManager.nextGuardState(from: .swallowing, given: .swallowThenDisarm) == .swallowingThenDisarm)
    }

    @Test("A disarm waits for a pending mouse-up but is immediate when idle")
    func disarmRequests() {
        #expect(HIDEventManager.nextGuardState(from: .idle, given: .disarmRequested) == .idle)
        #expect(HIDEventManager.nextGuardState(from: .swallowing, given: .disarmRequested) == .swallowingThenDisarm)
        #expect(HIDEventManager.nextGuardState(from: .swallowingThenDisarm, given: .disarmRequested) == .swallowingThenDisarm)
    }

    @Test("Only clicks inside the region and the double-click window are swallowed")
    func swallowRegion() {
        let region = CGRect(x: 100, y: 0, width: 50, height: 24)
        let inside = CGPoint(x: 120, y: 10)
        let outside = CGPoint(x: 10, y: 10)
        #expect(HIDEventManager.shouldSwallowClick(clickLocation: inside, guardRegion: region, isDoubleClick: false, withinDoubleClickWindow: true))
        #expect(!HIDEventManager.shouldSwallowClick(clickLocation: outside, guardRegion: region, isDoubleClick: true, withinDoubleClickWindow: true))
        #expect(!HIDEventManager.shouldSwallowClick(clickLocation: inside, guardRegion: region, isDoubleClick: true, withinDoubleClickWindow: false))
    }
}

/// The table of named keys.
@Suite("Key code table")
struct KeyCodeTableTests {
    private static let namedKeys: [KeyCode] = [.a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z, .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .grave, .minus, .equal, .leftBracket, .rightBracket, .backslash, .semicolon, .quote, .comma, .period, .slash, .space, .tab, .returnKey, .delete, .forwardDelete, .escape, .help, .home, .end, .pageUp, .pageDown, .leftArrow, .rightArrow, .upArrow, .downArrow, .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20, .capsLock, .function, .control, .rightControl, .option, .rightOption, .shift, .rightShift, .command, .rightCommand, .keypad0, .keypad1, .keypad2, .keypad3, .keypad4, .keypad5, .keypad6, .keypad7, .keypad8, .keypad9, .keypadDecimal, .keypadPlus, .keypadMinus, .keypadMultiply, .keypadDivide, .keypadEquals, .keypadClear, .keypadEnter, .volumeUp, .volumeDown, .mute]

    @Test("Every named key has its own valid code")
    func distinctValidCodes() {
        #expect(!Self.namedKeys.contains { !$0.isValid })
        #expect(Set(Self.namedKeys).count == Self.namedKeys.count)
    }

    @Test("Named keys use the platform's virtual key codes")
    func platformCodes() {
        #expect(KeyCode.a.rawValue == 0)
        #expect(KeyCode.space.rawValue == 49)
        #expect(KeyCode.escape.rawValue == 53)
        #expect(KeyCode.f1.rawValue == 122)
    }
}

/// System-reserved combinations, read from the system's symbolic hotkeys without changing them.
@MainActor
@Suite("System-reserved key combinations")
struct SystemReservedCombinationTests {
    @Test("Every modifier on F20 is a combination the system leaves free")
    func unusedKeyIsFree() {
        #expect(!KeyCombination(key: .f20, modifiers: [.control, .option, .shift, .command]).isSystemReserved)
    }
}
