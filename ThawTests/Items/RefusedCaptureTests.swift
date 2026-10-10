//
//  RefusedCaptureTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

@MainActor
@Suite("A capture refused because no Thaw surface is open is not a failed read")
struct RefusedCaptureTests {
    private func makeItem(_ title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: .string("com.example.status"), title: title, instanceIndex: 0),
            windowID: 101,
            ownerPID: 999_991,
            sourcePID: 999_991,
            bounds: CGRect(x: 1000, y: 4.5, width: 24, height: 24),
            title: title,
            isOnScreen: true
        )
    }

    @Test("A refused capture leaves the cached pictures alone")
    func refusedCaptureInvalidatesNothing() {
        var pass = MenuBarItemImageCache.CapturePass()

        let recorded = pass.noteMissingCapture(of: [makeItem("A"), makeItem("B")], captureWasAllowed: false)

        #expect(!recorded)
        #expect(pass.unreadable.isEmpty)
        #expect(pass.invalidatedTags.isEmpty)
    }

    @Test("A capture that was allowed and still returned nothing is a failure")
    func failedCaptureInvalidates() {
        var pass = MenuBarItemImageCache.CapturePass()
        let items = [makeItem("A"), makeItem("B")]

        let recorded = pass.noteMissingCapture(of: items, captureWasAllowed: true)

        #expect(recorded)
        #expect(pass.unreadable.count == 2)
        #expect(pass.invalidatedTags == Set(items.map(\.tag)))
    }
}
