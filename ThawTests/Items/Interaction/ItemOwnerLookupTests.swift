//
//  ItemOwnerLookupTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel
import Testing
@testable import Thaw

/// A click is aimed at the item's owning process, so an item listed without one needs it found by bundle ID.
@Suite("Item owner lookup")
struct ItemOwnerLookupTests {
    private func item(_ namespace: MenuBarItemTag.Namespace, owner: pid_t, source: pid_t? = nil) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(namespace: namespace, title: "Item-0", windowID: 7, instanceIndex: 0),
            windowID: 7,
            ownerPID: owner,
            sourcePID: source,
            bounds: CGRect(x: 900, y: 4, width: 24, height: 24),
            title: nil,
            isOnScreen: true
        )
    }

    private let lulu = MenuBarItemTag.Namespace.string("com.objective-see.lulu.app")

    @Test("An item with an owner keeps it, and the running apps are never asked")
    func knownOwnerIsKept() {
        var asked = false
        let pid = ItemOwnerLookup.pid(for: item(lulu, owner: 300, source: 412)) { _ in
            asked = true
            return [999]
        }
        #expect(pid == 412)
        #expect(!asked)
    }

    @Test("An item listed with no owner takes the one running app its bundle ID names")
    func unownedItemFindsItsApp() {
        var askedFor: String?
        let pid = ItemOwnerLookup.pid(for: item(lulu, owner: 0)) { bundleID in
            askedFor = bundleID
            return [812]
        }
        #expect(pid == 812)
        #expect(askedFor == "com.objective-see.lulu.app")
    }

    @Test("No running app, or two of them, leaves the item without an owner")
    func noSingleAppLeavesItUnowned() {
        #expect(ItemOwnerLookup.pid(for: item(lulu, owner: 0)) { _ in [] } == 0)
        #expect(ItemOwnerLookup.pid(for: item(lulu, owner: 0)) { _ in [812, 813] } == 0)
    }

    @Test("The running apps are found by bundle ID, this one among them, and an owned item keeps its owner")
    func realLookupFindsThisProcess() throws {
        let bundleID = try #require(Bundle.main.bundleIdentifier)
        #expect(ItemOwnerLookup.runningPIDs(forBundleID: bundleID).contains(ProcessInfo.processInfo.processIdentifier))
        #expect(ItemOwnerLookup.pid(for: item(.string(bundleID), owner: 300)) == 300)
    }

    @Test("An item whose identity names no bundle ID stays without an owner")
    func noBundleIDLeavesItUnowned() {
        #expect(ItemOwnerLookup.pid(for: item(.null, owner: 0)) { _ in [812] } == 0)
    }

    // MARK: resolving

    @Test("An item listed with no owner gets its app's process as owner and source")
    func resolvingFillsTheProcess() {
        // Backblaze, opened from the Thaw Bar before Thaw had seen it this session.
        let resolved = ItemOwnerLookup.resolving(item(lulu, owner: 0)) { _ in [1033] }

        #expect(resolved.ownerPID == 1033)
        #expect(resolved.sourcePID == 1033)
        #expect(resolved.reactionPIDs == [1033])
        #expect(resolved.tag == item(lulu, owner: 0).tag)
        #expect(resolved.bounds == item(lulu, owner: 0).bounds)
    }

    @Test("A hosted item missing only its source keeps MenuBarAgent as owner")
    func resolvingKeepsTheHost() {
        let resolved = ItemOwnerLookup.resolving(item(lulu, owner: 786, source: 0)) { _ in [1033] }

        #expect(resolved.ownerPID == 786)
        #expect(resolved.sourcePID == 1033)
    }

    @Test("An item with a process, or whose app can't be told apart, is left as it is")
    func resolvingLeavesTheRest() {
        var asked = false
        let owned = ItemOwnerLookup.resolving(item(lulu, owner: 300, source: 412)) { _ in
            asked = true
            return [999]
        }
        #expect(owned.ownerPID == 300 && owned.sourcePID == 412)
        #expect(!asked)

        let ambiguous = ItemOwnerLookup.resolving(item(lulu, owner: 0)) { _ in [812, 813] }
        #expect(ambiguous.ownerPID == 0 && ambiguous.sourcePID == nil)
    }
}
