//
//  ConcealedOrderGuardTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

struct ConcealedOrderGuardTests {
    /// The table from the report: a Hidden re-space renumbered WiFi, Thaw Space and Widgets past the
    /// Always Hidden divider (439), and the next launch read them as Always Hidden.
    private let before = ["flux": 429, "wifi": 322, "space": 321, "widgets": 295, "passwords": 300, "alwaysHiddenDivider": 439]
    private let after = ["flux": 953, "wifi": 853, "space": 753, "widgets": 453, "passwords": 153, "alwaysHiddenDivider": 439]

    @Test("A write that renumbers another section's items is undone, members included")
    func undoesCrossSectionWrite() throws {
        let restored = try #require(ConcealedOrderGuard.rollback(
            changed: ["flux", "wifi", "space", "widgets", "passwords"],
            memberKeys: ["flux", "passwords"],
            before: before,
            current: after
        ))
        #expect(restored == before)
    }

    @Test("A write that changes only the section's own items stands")
    func keepsMemberOnlyWrite() {
        #expect(ConcealedOrderGuard.rollback(
            changed: ["flux", "passwords"],
            memberKeys: ["flux", "passwords"],
            before: before,
            current: after
        ) == nil)
    }

    @Test("An empty write needs nothing undone")
    func ignoresEmptyWrite() {
        #expect(ConcealedOrderGuard.rollback(changed: [], memberKeys: ["flux"], before: before, current: before) == nil)
    }

    @Test("Undoing keeps keys the write didn't touch as they are now, and removes keys it added")
    func restoresOnlyChangedKeys() throws {
        let current = ["flux": 953, "wifi": 853, "clock": 10, "added": 77]
        let restored = try #require(ConcealedOrderGuard.rollback(
            changed: ["flux", "wifi", "added"],
            memberKeys: ["flux"],
            before: ["flux": 429, "wifi": 322, "clock": 12],
            current: current
        ))
        #expect(restored == ["flux": 429, "wifi": 322, "clock": 10])
    }
}
