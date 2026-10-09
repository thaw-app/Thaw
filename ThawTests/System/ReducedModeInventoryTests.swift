//
//  ReducedModeInventoryTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@MainActor
struct ReducedModeInventoryTests {
    private func app(_ bundleID: String?, _ name: String? = nil, background: Bool = false) -> ReducedModeInventory.Running {
        .init(bundleID: bundleID, name: name, isBackgroundOnly: background)
    }

    @Test
    func `lists other developers' apps by name and leaves out Thaw, Apple and background processes`() {
        let apps = ReducedModeInventory.candidates(
            running: [
                app("com.example.zeta", "Zeta"),
                app("com.apple.Safari", "Safari"),
                app("com.stonerl.Thaw", "Thaw"),
                app("com.example.daemon", "Daemon", background: true),
                app(nil, "Nameless"),
                app("com.example.alpha", "alpha"),
            ],
            tableKeys: nil,
            isOwn: { $0 == "com.stonerl.Thaw" }
        )
        #expect(apps.map(\.bundleID) == ["com.example.alpha", "com.example.zeta"])
    }

    @Test
    func `keeps only apps with a row in the position table when the table can be read`() {
        let apps = ReducedModeInventory.candidates(
            running: [app("com.example.withitem", "With"), app("com.example.noitem", "Without")],
            tableKeys: ["status:com.example.withitem::Item-0", "module:Clock"],
            isOwn: { _ in false }
        )
        #expect(apps.map(\.bundleID) == ["com.example.withitem"])
    }

    @Test
    func `lists an app once when it runs twice, under whichever name it has`() {
        let apps = ReducedModeInventory.candidates(
            running: [app("com.example.twice", nil), app("com.example.twice", "Twice"), app("com.example.bare", nil)],
            tableKeys: nil,
            isOwn: { _ in false }
        )
        #expect(apps == [
            ReducedModeApp(bundleID: "com.example.bare", name: "com.example.bare"),
            ReducedModeApp(bundleID: "com.example.twice", name: "Twice"),
        ])
    }

    @Test
    func `maps each hidden app to an identifier the kit can conceal`() {
        let input = ReducedModeHider.input(hiding: ["com.example.b", "com.example.a"])
        #expect(input.assignment == ["reduced:com.example.a": .hidden, "reduced:com.example.b": .hidden])
        #expect(input.owners == ["reduced:com.example.a": "com.example.a", "reduced:com.example.b": "com.example.b"])
    }
}
