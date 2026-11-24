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

    @Test("Only a ten-character uppercase team identifier is dropped")
    func dropsOnlyTeamIdentifier() {
        #expect(MenuBarItemTag.withoutTeamIdentifierPrefix(appStoreHelper) == "com.bjango.istatmenus-mas.status")
        #expect(MenuBarItemTag.withoutTeamIdentifierPrefix("com.bjango.istatmenus.status")
            == "com.bjango.istatmenus.status")
        #expect(MenuBarItemTag.withoutTeamIdentifierPrefix("eu.exelban.Stats") == "eu.exelban.Stats")
        #expect(MenuBarItemTag.withoutTeamIdentifierPrefix("y93tk974at.com.example") == "y93tk974at.com.example")
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
