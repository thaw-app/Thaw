//
//  AXSubprocessMappingTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw
import ThawAXCore

/// Subprocess walks return raw observations; app-side identity and assembly must match the in-process path.
@Suite("AX subprocess observation mapping")
struct AXSubprocessMappingTests {
    private func observation(
        bundleID: String?,
        title: String? = nil,
        identifier: String? = nil,
        description: String? = nil,
        x: CGFloat,
        isOverflow: Bool = false
    ) -> AXItemObservation {
        AXItemObservation(
            bundleID: bundleID,
            processName: nil,
            ownerPID: 100,
            identifier: identifier,
            accessibilityDescription: description,
            title: title,
            help: nil,
            frame: CGRect(x: x, y: 0, width: 24, height: 24),
            isOverflowControl: isOverflow
        )
    }

    @Test("overflow control is not an item")
    func overflowDropped() {
        let items = MenuBarItemAXProvider.items(fromSubprocess: [
            observation(bundleID: "com.apple.MenuBarAgent", title: "Chevron", x: 0, isOverflow: true),
            observation(bundleID: "com.example.app", title: "Widget", x: 40),
        ])
        #expect(items.count == 1)
        #expect(items[0].tag.title == "Widget")
    }

    @Test("a titled app item keeps its namespace, title, and frame")
    func titledItem() {
        let items = MenuBarItemAXProvider.items(fromSubprocess: [
            observation(bundleID: "com.example.app", identifier: "Widget", x: 10),
        ])
        #expect(items.count == 1)
        #expect(items[0].tag.namespace == .string("com.example.app"))
        #expect(items[0].tag.title == "Widget")
        #expect(items[0].bounds == CGRect(x: 10, y: 0, width: 24, height: 24))
        #expect(items[0].ownerPID == 100)
    }

    @Test("nameless siblings get positional fallback titles and distinct ids")
    func fallbackTitles() {
        let items = MenuBarItemAXProvider.items(fromSubprocess: [
            observation(bundleID: "com.example.app", x: 10),
            observation(bundleID: "com.example.app", x: 40),
        ])
        #expect(items.count == 2)
        #expect(items[0].tag.title == "Item-0")
        #expect(items[1].tag.title == "Item-1")
        #expect(items[0].windowID != items[1].windowID)
    }
}
