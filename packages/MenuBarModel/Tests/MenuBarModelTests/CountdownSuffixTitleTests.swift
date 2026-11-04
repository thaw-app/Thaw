//
//  CountdownSuffixTitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("Countdown suffix titles")
struct CountdownSuffixTitleTests {
    @Test("A Cron event counting down keeps one identity, and another event gets its own")
    func cronCountdownCollapses() {
        let bundle = "com.cron.electron"
        let minutes = Set(["🤸🏻Sara gymnastics · 13 m left", "🤸🏻Sara gymnastics · 12 m left", "🤸🏻Sara gymnastics · 1 m left"]
            .map { MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):\($0)") })
        #expect(minutes == ["\(bundle):🤸🏻Sara gymnastics · # m left"])
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Standup · 5 m left") != minutes.first)
    }
}
