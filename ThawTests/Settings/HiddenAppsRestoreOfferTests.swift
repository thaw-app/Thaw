//
//  HiddenAppsRestoreOfferTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
struct HiddenAppsRestoreOfferTests {
    private typealias Rule = HiddenAppsRestoreOfferRule

    @MainActor
    private final class Harness {
        var candidates = ["com.example.one", "com.example.two"]
        var answered = false
        var shown: Set<String>?
        var failsShow = false
        var lookups = 0

        func offer() -> HiddenAppsRestoreOffer {
            HiddenAppsRestoreOffer(environment: .init(
                findCandidates: {
                    self.lookups += 1
                    return self.candidates
                },
                showApps: {
                    if self.failsShow {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    self.shown = $0
                    return $0.sorted()
                },
                isAnswered: { self.answered },
                markAnswered: { self.answered = true }
            ))
        }
    }

    private func due(_ candidates: [String], answered: Bool, attention: Bool, sheet: Bool, drag: Bool) -> Bool {
        Rule.shouldOffer(
            candidates: candidates,
            alreadyAnswered: answered,
            journalNeedsAttention: attention,
            isAnotherSheetShowing: sheet,
            isDraggingMenuBarItem: drag
        )
    }

    private func present(_ offer: HiddenAppsRestoreOffer) {
        offer.presentIfDue(journalNeedsAttention: false, isAnotherSheetShowing: false, isDraggingMenuBarItem: false)
    }

    @Test("The offer is made when there are candidates and nothing stands in the way")
    func offersWhenDue() {
        #expect(due(["a"], answered: false, attention: false, sheet: false, drag: false))
    }

    @Test("No candidates, an earlier answer, an unreadable record, another sheet or a drag each hold it back")
    func eachConditionHoldsItBack() {
        #expect(!due([], answered: false, attention: false, sheet: false, drag: false))
        #expect(!due(["a"], answered: true, attention: false, sheet: false, drag: false))
        #expect(!due(["a"], answered: false, attention: true, sheet: false, drag: false))
        #expect(!due(["a"], answered: false, attention: false, sheet: true, drag: false))
        #expect(!due(["a"], answered: false, attention: false, sheet: false, drag: true))
    }

    @Test("Candidates are presented with nothing selected")
    func presentsUnselected() {
        let harness = Harness()
        let offer = harness.offer()
        offer.captureCandidates()
        present(offer)
        #expect(offer.isPresented)
        #expect(offer.candidates == harness.candidates)
        #expect(offer.selectedBundleIDs.isEmpty)
    }

    @Test("An earlier answer skips the lookup and the offer")
    func answeredSkipsLookup() {
        let harness = Harness()
        harness.answered = true
        let offer = harness.offer()
        offer.captureCandidates()
        present(offer)
        #expect(harness.lookups == 0)
        #expect(!offer.isPresented)
    }

    @Test("Show Selected switches on only the picked apps and does not ask again")
    func showSelectedShowsOnlyThePick() {
        let harness = Harness()
        let offer = harness.offer()
        offer.captureCandidates()
        present(offer)
        offer.showSelected()
        #expect(harness.shown == nil, "Nothing is shown without a selection")
        offer.selectedBundleIDs = ["com.example.two"]
        offer.showSelected()
        #expect(harness.shown == ["com.example.two"])
        #expect(harness.answered)
        #expect(!offer.isPresented)
        present(offer)
        #expect(!offer.isPresented)
    }

    @Test("Keep Hidden shows nothing and does not ask again")
    func keepHiddenShowsNothing() {
        let harness = Harness()
        let offer = harness.offer()
        offer.captureCandidates()
        present(offer)
        offer.keepHidden()
        #expect(harness.shown == nil)
        #expect(harness.answered)
        #expect(!offer.isPresented)
    }

    @Test("A failed switch keeps the sheet and the selection for another try")
    func failedShowKeepsTheSheet() {
        let harness = Harness()
        harness.failsShow = true
        let offer = harness.offer()
        offer.captureCandidates()
        present(offer)
        offer.selectedBundleIDs = ["com.example.one"]
        offer.showSelected()
        #expect(offer.isPresented)
        #expect(offer.errorMessage != nil)
        #expect(offer.selectedBundleIDs == ["com.example.one"])
        #expect(!harness.answered)
    }

    @Test("Setting a record aside asks again even after an earlier answer")
    func setAsideAsksAgain() {
        let harness = Harness()
        harness.answered = true
        let offer = harness.offer()
        offer.offerAfterSettingRecordAside()
        #expect(offer.isPresented)
        #expect(offer.candidates == harness.candidates)
        harness.candidates = []
        offer.keepHidden()
        offer.offerAfterSettingRecordAside()
        #expect(!offer.isPresented)
    }
}
