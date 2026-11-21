//
//  ThawBarPointerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Testing
@testable import Thaw

/// Whether the pointer counts as on the Thaw Bar, which keeps revealed items from hiding.
@Suite("Thaw Bar pointer")
struct ThawBarPointerTests {
    private static let frame = CGRect(x: 800, y: 900, width: 300, height: 40)

    @Test("The pointer over an open bar, or just off its edge, is on it")
    func openBar() {
        #expect(HIDEventManager.isPointer(CGPoint(x: 900, y: 920), overThawBarAt: Self.frame, isVisible: true))
        #expect(HIDEventManager.isPointer(CGPoint(x: 790, y: 920), overThawBarAt: Self.frame, isVisible: true))
        #expect(!HIDEventManager.isPointer(CGPoint(x: 700, y: 920), overThawBarAt: Self.frame, isVisible: true))
    }

    @Test("A closed bar's last frame doesn't count, so items revealed inline can hide")
    func closedBar() {
        #expect(!HIDEventManager.isPointer(CGPoint(x: 900, y: 920), overThawBarAt: Self.frame, isVisible: false))
    }

    @Test("No pointer location is never on the bar")
    func noPointer() {
        #expect(!HIDEventManager.isPointer(nil, overThawBarAt: Self.frame, isVisible: true))
    }
}
