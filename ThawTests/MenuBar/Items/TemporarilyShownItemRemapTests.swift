//
//  TemporarilyShownItemRemapTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// The windowID re-map `temporarilyShow` applies before looking up the return destination.
///
/// On a cold start the cache can hold fallback tags (`com.apple.controlcenter:Item-0:N`)
/// while the fresh fetch has real ones, so `getReturnDestination` returns nil and
/// every IceBar click fails with `showFailed` (#943). The window ID is stable
/// across resolution, so the stale item is re-mapped by it.
@Suite("Temporarily shown item re-map")
struct TemporarilyShownItemRemapTests {
    private func item(
        namespace: MenuBarItemTag.Namespace,
        title: String,
        windowID: CGWindowID,
        instanceIndex: Int = 0,
        sourcePID: pid_t? = nil
    ) -> MenuBarItem {
        MenuBarItem(
            tag: MenuBarItemTag(
                namespace: namespace,
                title: title,
                windowID: windowID,
                instanceIndex: instanceIndex
            ),
            windowID: windowID,
            ownerPID: 2559,
            sourcePID: sourcePID,
            bounds: .zero,
            title: title,
            isOnScreen: true
        )
    }

    /// The caller's tag is an unresolved fallback; the fresh list has the resolved one (#943).
    @Test("A stale fallback tag is re-mapped onto the resolved item by windowID")
    func staleFallbackTagIsRemappedByWindowID() {
        let stale = item(namespace: .controlCenter, title: "Item-0", windowID: 13377, instanceIndex: 5)
        let resolved = item(namespace: .string("io.tailscale.ipn.macos"), title: "Item-0", windowID: 13377, sourcePID: 501)
        let other = item(namespace: .string("com.if.Amphetamine"), title: "Amphetamine", windowID: 379, sourcePID: 502)

        let remapped = MenuBarItemManager.remappedItem(for: stale, in: [other, resolved])

        #expect(remapped.tag == resolved.tag)
        #expect(remapped.sourcePID == 501)
    }

    @Test("An item whose tag is present is returned unchanged")
    func presentTagIsReturnedUnchanged() {
        let current = item(namespace: .string("io.tailscale.ipn.macos"), title: "Item-0", windowID: 13377, sourcePID: 501)

        let remapped = MenuBarItemManager.remappedItem(for: current, in: [current])

        #expect(remapped.tag == current.tag)
    }

    /// An app that quit between click and fetch must not re-map onto an unrelated item.
    @Test("A vanished window is returned unchanged")
    func vanishedWindowIsReturnedUnchanged() {
        let stale = item(namespace: .controlCenter, title: "Item-0", windowID: 13377, instanceIndex: 5)
        let unrelated = item(namespace: .string("com.if.Amphetamine"), title: "Amphetamine", windowID: 379, sourcePID: 502)

        let remapped = MenuBarItemManager.remappedItem(for: stale, in: [unrelated])

        #expect(remapped.tag == stale.tag)
        #expect(remapped.windowID == stale.windowID)
    }
}
