//
//  MenuBarItemIdentityAccessorsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
@testable import MenuBarModel
import Testing

@Suite("Item identity accessors")
struct MenuBarItemIdentityAccessorsTests {
    private func item(namespace: MenuBarItemTag.Namespace, title: String) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: title),
            windowID: 0x9000_0001,
            ownerPID: 700,
            sourcePID: 700,
            bounds: CGRect(x: 1117, y: 0, width: 24, height: 22),
            title: title,
            isOnScreen: true
        )
    }

    @Test("An item's canonical identifier is its unique identifier, canonicalized")
    func canonicalIdentifier() {
        let plain = item(namespace: .string("com.example.app"), title: "Item-0")
        #expect(plain.canonicalIdentifier == MenuBarItemTag.canonicalPersistentIdentifier(plain.uniqueIdentifier))

        // Rectangle's AppKit placeholder title is the one the canonical form rewrites.
        let placeholder = item(namespace: .string("com.knollsoft.Rectangle"), title: "_NS:8")
        #expect(placeholder.canonicalIdentifier == MenuBarItemTag.canonicalPersistentIdentifier(placeholder.uniqueIdentifier))
    }

    @Test("Only a string namespace names a bundle identifier")
    func namespaceBundleIdentifier() {
        #expect(MenuBarItemTag.Namespace.string("com.example.app").bundleIdentifier == "com.example.app")
        #expect(MenuBarItemTag.Namespace.null.bundleIdentifier == nil)
        #expect(MenuBarItemTag.Namespace.uuid(UUID()).bundleIdentifier == nil)
    }

    @Test("Apple's bundle identifiers are the ones under com.apple.")
    func appleBundleIdentifier() {
        #expect(SharedConstants.isAppleBundleIdentifier("com.apple.controlcenter"))
        #expect(!SharedConstants.isAppleBundleIdentifier("com.applesauce.app"))
        #expect(!SharedConstants.isAppleBundleIdentifier("com.example.app"))
    }

    @Test("The active menu bar display is the one the optional read names")
    func activeMenuBarDisplay() {
        #expect(Bridging.activeMenuBarDisplayID == Bridging.getActiveMenuBarDisplayID() ?? CGMainDisplayID())
    }
}
