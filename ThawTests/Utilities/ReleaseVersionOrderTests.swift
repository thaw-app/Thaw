//
//  ReleaseVersionOrderTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

@Suite("Release versions order by semantic-version precedence")
struct ReleaseVersionOrderTests {
    @Test("Prerelease numbers compare as numbers", arguments: [
        ("3.0.0-alpha.9", "3.0.0-alpha.10"),
        ("3.0.0-alpha.1", "3.0.0-alpha.2"),
        ("3.0.0-alpha.10", "3.0.0-beta.1"),
        ("3.0.0-alpha", "3.0.0-alpha.1"),
        ("3.0.0-alpha.10", "3.0.0"),
        ("2.4.1", "3.0.0-alpha.1"),
        ("3.0", "3.0.1"),
        ("3.0.0-1", "3.0.0-alpha"),
        ("3.0.0-alpha.9+build.5", "3.0.0-alpha.10"),
    ])
    func earlierPrecedesLater(earlier: String, later: String) {
        #expect(ReleaseVersionOrder.precedes(earlier, later))
        #expect(!ReleaseVersionOrder.precedes(later, earlier))
    }

    @Test("The prerelease tag drops the core and the build", arguments: [
        ("3.0.0-alpha.10", "alpha.10"),
        ("3.0.0-alpha.10+116", "alpha.10"),
        ("2.0.1-rc.2", "rc.2"),
        ("3.0.0", nil),
        ("3.0.0+116", nil),
    ] as [(String, String?)])
    func prereleaseTag(version: String, tag: String?) {
        #expect(ReleaseVersionOrder.prereleaseTag(of: version).map(String.init) == tag)
    }

    @Test("A version does not precede itself")
    func equalVersions() {
        #expect(!ReleaseVersionOrder.precedes("3.0.0-alpha.10", "3.0.0-alpha.10"))
        #expect(!ReleaseVersionOrder.precedes("3.0.0", "3.0"))
    }
}
