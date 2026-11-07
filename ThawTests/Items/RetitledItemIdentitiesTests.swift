//
//  RetitledItemIdentitiesTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import Testing
@testable import Thaw

/// A read that misses an item's identifier keeps the identity the item had, per app (#1489).
@Suite("Retitled item identities")
struct RetitledItemIdentitiesTests {
    private typealias RawItem = MenuBarItemAXProvider.RawItem

    private func raw(_ identity: String, shows display: String, owner: pid_t, x: CGFloat) -> RawItem {
        RawItem(
            namespace: .string("com.raycast.macos"),
            identityTitle: identity,
            displayTitle: display,
            bounds: CGRect(x: x, y: 0, width: 80, height: 24),
            ownerPID: owner
        )
    }

    @Test("Raycast's calendar item keeps calendar-events when a read sees only its countdown")
    func keepsTheIdentifierAcrossAFallbackRead() {
        var memory = RetitleIdentityMemory()
        let stable = [
            raw("calendar-events", shows: "Standup • in 52m", owner: 42, x: 100),
            raw("clipboard-history", shows: "Clipboard", owner: 42, x: 200),
            raw("Other", shows: "Other", owner: 43, x: 300),
        ]
        #expect(RetitledItemIdentities.resolve(stable, with: &memory).map(\.identityTitle)
            == ["calendar-events", "clipboard-history", "Other"])

        let fallback = [
            raw("Standup • in 51m", shows: "Standup • in 51m", owner: 42, x: 100),
            raw("clipboard-history", shows: "Clipboard", owner: 42, x: 200),
            raw("Renamed", shows: "Renamed", owner: 43, x: 300),
        ]
        let resolved = RetitledItemIdentities.resolve(fallback, with: &memory)
        #expect(resolved.map(\.identityTitle) == ["calendar-events", "clipboard-history", "Renamed"])
        #expect(resolved[0].displayTitle == "Standup • in 51m", "the live title is still shown")
        #expect(resolved[0].bounds == fallback[0].bounds)
        _ = RetitledItemIdentities.resolve([])
    }
}
