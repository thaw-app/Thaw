//
//  StaleAliasTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

@Suite("Stale identifier aliases")
struct StaleAliasTests {
    private func pruned(_ titles: [String], bundleID: String) -> Set<String> {
        let identifiers = Set(titles.map { "\(bundleID):\($0)" })
        let kept = MenuBarItemTag.identifiersWithoutStaleAliases(identifiers, bundleID: bundleID)
        return Set(kept.map { String($0.dropFirst(bundleID.count + 1)) })
    }

    @Test("An AppKit placeholder name is dropped for any app")
    func appKitPlaceholderIsDropped() {
        #expect(pruned(["Item-0", "_NS:49"], bundleID: "com.stairways.keyboardmaestro.engine") == ["Item-0"])
        #expect(pruned(["Item-0", "_NS:12:1"], bundleID: "com.example.app") == ["Item-0"])
    }

    @Test("A real second item is kept")
    func realSiblingsAreKept() {
        #expect(pruned(["Item-0", "Item-1"], bundleID: "com.example.app") == ["Item-0", "Item-1"])
        #expect(pruned(["Item-0", "Named"], bundleID: "com.stairways.keyboardmaestro.engine") == ["Item-0", "Named"])
    }

    @Test("OneDrive's bare title is dropped once an account title is known")
    func oneDriveBareTitleIsAnAlias() {
        let bundleID = "com.microsoft.OneDrive"
        #expect(pruned(["OneDrive", "OneDrive \u{2014} Personal"], bundleID: bundleID) == ["OneDrive \u{2014} Personal"])
        // Two accounts stay two items.
        #expect(
            pruned(["OneDrive \u{2014} Personal", "OneDrive \u{2014} Work"], bundleID: bundleID)
                == ["OneDrive \u{2014} Personal", "OneDrive \u{2014} Work"]
        )
    }

    @Test("A bare OneDrive title on its own is kept, and other apps keep the title")
    func bareTitleAloneIsKept() {
        #expect(pruned(["OneDrive"], bundleID: "com.microsoft.OneDrive") == ["OneDrive"])
        #expect(pruned(["OneDrive", "OneDrive \u{2014} X"], bundleID: "com.example.app").count == 2)
    }
}
