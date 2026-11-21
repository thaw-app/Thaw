//
//  CapturedTagValidityTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Testing
@testable import Thaw

/// The set lookup keeps exactly the pictures the per-tag scan with matchesIgnoringWindowID kept.
@Suite("Captured tag validity")
struct CapturedTagValidityTests {
    private static let live = MenuBarItemTag(namespace: .string("com.example.chat"), title: "Item-0", windowID: 42)
    private static let fromDisk = MenuBarItemTag(namespace: .string("com.example.chat"), title: "Item-0", windowID: nil)
    private static let secondInstance = MenuBarItemTag(namespace: .string("com.example.chat"), title: "Item-0", windowID: nil, instanceIndex: 1)
    private static let otherApp = MenuBarItemTag(namespace: .string("com.example.other"), title: "Item-0", windowID: nil)
    private static let clock = MenuBarItemTag(namespace: .controlCenter, title: "Clock", windowID: 7)
    private static let clockElsewhere = MenuBarItemTag(namespace: .controlCenter, title: "Clock", windowID: 8)
    private static let wifi = MenuBarItemTag(namespace: .controlCenter, title: "WiFi", windowID: 7)

    @Test("An app's picture is kept whatever its window ID, but not another instance's or another app's")
    func ignoresWindowIDForApps() {
        let validity = CapturedTagValidity(keeping: [Self.live])
        #expect(validity.keeps(Self.fromDisk))
        #expect(!validity.keeps(Self.secondInstance))
        #expect(!validity.keeps(Self.otherApp))
    }

    @Test("A system item's picture is kept under its own tag, whose equality already leaves out the window ID")
    func systemItemsMatchByTag() {
        let validity = CapturedTagValidity(keeping: [Self.clock])
        #expect(validity.keeps(Self.clock))
        #expect(validity.keeps(Self.clockElsewhere))
        #expect(!validity.keeps(Self.wifi))
    }

    @Test("It answers as the per-tag scan did for every pair")
    func matchesTheScan() {
        let all = [Self.live, Self.fromDisk, Self.secondInstance, Self.otherApp, Self.clock, Self.clockElsewhere, Self.wifi]
        for kept in all {
            let validity = CapturedTagValidity(keeping: [kept])
            for tag in all {
                let scanned = tag.isSystemItem ? kept == tag : kept.matchesIgnoringWindowID(tag)
                #expect(validity.keeps(tag) == scanned, "\(tag) against \(kept)")
            }
        }
    }
}
