//
//  RestoreHiddenAppsSheetTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import Thaw

@MainActor
@Suite("Restore hidden apps sheet")
struct RestoreHiddenAppsSheetTests {
    /// An offer listing an installed app, so its row draws an icon, and one that isn't installed.
    private static func offer(failsShow: Bool = false) -> HiddenAppsRestoreOffer {
        let offer = HiddenAppsRestoreOffer(environment: .init(
            findCandidates: { ["com.apple.finder", "com.example.not-installed"] },
            showApps: { selected in
                if failsShow {
                    throw CocoaError(.fileWriteNoPermission)
                }
                return selected.sorted()
            },
            isAnswered: { false },
            markAnswered: {}
        ))
        offer.captureCandidates()
        return offer
    }

    private static func render(_ offer: HiddenAppsRestoreOffer) -> OffscreenRender<some View> {
        OffscreenRender(RestoreHiddenAppsSheet(offer: offer).frame(width: 480, height: 480), size: CGSize(width: 480, height: 480))
    }

    @Test("The sheet draws each candidate, and redraws when one is selected")
    func drawsCandidatesAndSelection() async throws {
        let offer = Self.offer()
        let render = Self.render(offer)
        let unselected = try render.pixels()
        #expect(unselected.contains { $0 != 0 })
        offer.selectedBundleIDs = ["com.example.not-installed"]
        var selected = unselected
        let redrawn = await render.settle {
            selected = (try? render.pixels()) ?? unselected
            return selected != unselected
        }
        #expect(redrawn)
    }

    @Test("A failed show draws its error under the list")
    func drawsTheError() async throws {
        let offer = Self.offer(failsShow: true)
        let render = Self.render(offer)
        let before = try render.pixels()
        offer.selectedBundleIDs = ["com.apple.finder"]
        offer.showSelected()
        #expect(offer.errorMessage != nil)
        let redrawn = await render.settle { (try? render.pixels()) != before }
        #expect(redrawn)
    }
}
