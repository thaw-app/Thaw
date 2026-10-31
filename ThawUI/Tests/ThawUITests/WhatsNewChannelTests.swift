//
//  WhatsNewChannelTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import ThawUI

@Suite("What's New channels")
struct WhatsNewChannelTests {
    @Test("A version's tag picks its channel", arguments: [
        ("3.0.0-alpha.11", UpdateChannel.alpha),
        ("3.0.0-alpha.4.1", .alpha),
        ("3.0.0-beta.3", .beta),
        ("2.0.1-rc.2", .beta),
        ("3.0.0", .stable),
        ("3.1.0", .stable),
    ])
    func channelFromVersion(version: String, channel: UpdateChannel) {
        #expect(UpdateChannel(version: version) == channel)
    }

    @Test("Each channel keeps its own releases in file order")
    @MainActor
    func splitsReleases() {
        let document = ChangelogDocument.parse("""
        ## [3.0.0-alpha.11] - 2026-10-19

        - Alpha.

        ## [3.0.0-beta.3] - 2026-10-19

        - Beta.

        ## [3.0.0-alpha.10] - 2026-10-18

        - Older alpha.
        """)
        let releases = ChangelogDocument.displayReleases(in: document)
        let alpha = releases.filter { UpdateChannel(version: $0.version) == .alpha }.map(\.version)
        let beta = releases.filter { UpdateChannel(version: $0.version) == .beta }.map(\.version)
        #expect(alpha == ["3.0.0-alpha.11", "3.0.0-alpha.10"])
        #expect(beta == ["3.0.0-beta.3"])
        #expect(!releases.contains { UpdateChannel(version: $0.version) == .stable })
    }

    @Test("Each channel tab has its own icon")
    func channelIcons() {
        #expect(Set(UpdateChannel.allCases.map(\.systemImage)).count == UpdateChannel.allCases.count)
    }

    @Test("What's New has a tab for every channel, Stable first")
    func channelTabs() {
        #expect(UpdateChannel.allCases == [.stable, .beta, .alpha])
    }
}
