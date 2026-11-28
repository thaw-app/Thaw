//
//  TeamIdentifierPrefixTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@testable import MenuBarModel
import Testing

/// The Mac App Store iStat Menus helper is `Y93TK974AT.com.bjango.istatmenus-mas.status`;
/// its team identifier must not keep it from the iStat title rules.
@Suite("Team identifier prefix")
struct TeamIdentifierPrefixTests {
    private let appStoreHelper = "Y93TK974AT.com.bjango.istatmenus-mas.status"

    @Test("The Mac App Store iStat helper has dynamic metric titles")
    func appStoreHelperMatches() {
        #expect(MenuBarItemTag.hasDynamicMetricTitles(appStoreHelper))
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("Y93TK974AT.com.bjango.istatmenus-mas.agent"))
    }

    @Test("Only a ten-character uppercase team identifier is ignored", arguments: [
        "y93tk974at.com.bjango.istatmenus-mas.status",
        "Y93TK974A.com.bjango.istatmenus-mas.status",
        "Y93TK974AT.com.example.status",
    ])
    func malformedOrForeignPrefixDoesNotMatch(_ bundleID: String) {
        #expect(!MenuBarItemTag.hasDynamicMetricTitles(bundleID))
    }

    @Test("The prefix is dropped only when ten uppercase letters or digits come before a dot", arguments: [
        ("Y93TK974AT.com.example", "com.example"),
        ("Y93TK974AT.", ""),
        ("com.example", "com.example"),
        ("Y93TK974ATX.com.example", "Y93TK974ATX.com.example"),
        ("Y93TK974AÉ.com.example", "Y93TK974AÉ.com.example"),
        ("Y93", "Y93"),
    ])
    func prefixIsDroppedExactly(_ bundleID: String, _ expected: String) {
        #expect(MenuBarItemTag.withoutTeamIdentifierPrefix(bundleID) == expected)
    }

    @Test("A team-prefixed app outside the matchers keeps ordinal titles distinct")
    func foreignTeamPrefixedTitlesStayDistinct() {
        let bundle = "Y93TK974AT.com.example.status"
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Fan 1")
                != MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Fan 2")
        )
    }

    @Test("Metric ticks from the Mac App Store helper share one identity")
    func appStoreIdentifierCanonicalizes() {
        let first = MenuBarItemTag.canonicalPersistentIdentifier("\(appStoreHelper):CPU 11%")
        let second = MenuBarItemTag.canonicalPersistentIdentifier("\(appStoreHelper):CPU 27%")
        let quiet = MenuBarItemTag.canonicalPersistentIdentifier("\(appStoreHelper):Upload 1 KB/s, Download 2 KB/s")
        let busy = MenuBarItemTag.canonicalPersistentIdentifier("\(appStoreHelper):Upload 10 KB/s, Download 15 KB/s")

        #expect(first == second)
        #expect(first == "\(appStoreHelper):CPU #%")
        #expect(quiet == busy)
    }
}
