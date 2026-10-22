//
//  DrawnOnlyItemsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import MenuBarModel
import PlatformRuntimeKit
import Testing
@testable import Thaw
import ThawAXCore

@MainActor
struct DrawnOnlyItemsTests {
    typealias RawItem = MenuBarItemAXProvider.RawItem

    private let silentPID: pid_t = 40
    private let app = DrawnOnlyItems.App(bundleID: "com.example.silent", localizedName: "Silent")
    private let silentFrame = CGRect(x: 1200, y: 0, width: 30, height: 30)

    private func entry(_ pid: pid_t, x: CGFloat, width: CGFloat = 30) -> MenuBarAgentWindow.Entry {
        MenuBarAgentWindow.Entry(ownerPID: pid, frame: CGRect(x: x, y: 0, width: width, height: 30))
    }

    private func axItem(_ pid: pid_t, x: CGFloat, namespace: MenuBarItemTag.Namespace = .string("com.example.other")) -> RawItem {
        RawItem(namespace: namespace, identityTitle: "Item-0", displayTitle: "Item-0", bounds: CGRect(x: x, y: 4, width: 24, height: 22), ownerPID: pid)
    }

    private func select(
        _ entries: [MenuBarAgentWindow.Entry],
        answeredEmpty: Set<pid_t>,
        excluded: Set<pid_t> = [],
        apps: [pid_t: DrawnOnlyItems.App]? = nil,
        axItems: [RawItem] = []
    ) -> DrawnOnlyItems.Selection {
        DrawnOnlyItems.silentDrawnOwners(
            entries: entries,
            answeredEmpty: answeredEmpty,
            excluded: excluded,
            apps: apps ?? [silentPID: app],
            axItems: axItems
        )
    }

    // MARK: Selection

    @Test
    func `selects a drawn owner that answered empty this pass`() {
        let selection = select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID])
        #expect(selection.owners == [silentPID: entry(silentPID, x: 1200)])
        #expect(selection.multiEntryOwners.isEmpty)
    }

    @Test
    func `leaves out an owner that was not answered empty this pass`() {
        #expect(select([entry(silentPID, x: 1200)], answeredEmpty: []).owners.isEmpty)
    }

    @Test
    func `leaves out excluded pids`() {
        #expect(select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID], excluded: [silentPID]).owners.isEmpty)
    }

    @Test
    func `leaves out owners that are not running or have no bundle id`() {
        #expect(select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID], apps: [:]).owners.isEmpty)
        let unnamed = [silentPID: DrawnOnlyItems.App(bundleID: nil, localizedName: "Silent")]
        #expect(select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID], apps: unnamed).owners.isEmpty)
    }

    @Test
    func `leaves out this app's and MenuBarAgent's namespaces`() {
        let agent = [silentPID: DrawnOnlyItems.App(bundleID: SharedConstants.menuBarHostingBundleID, localizedName: nil)]
        #expect(select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID], apps: agent).owners.isEmpty)
        let own = [silentPID: DrawnOnlyItems.App(bundleID: ThawMenuBarIdentity.bundleIdentifier, localizedName: nil)]
        #expect(select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID], apps: own).owners.isEmpty)
    }

    @Test
    func `leaves out an entry an AX item of this pass already covers`() {
        let covered = select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID], axItems: [axItem(7, x: 1203)])
        #expect(covered.owners.isEmpty)
        let neighbour = select([entry(silentPID, x: 1200)], answeredEmpty: [silentPID], axItems: [axItem(7, x: 1222)])
        #expect(neighbour.owners.keys.sorted() == [silentPID])
    }

    @Test
    func `skips an owner with more than one drawn entry`() {
        let selection = select([entry(silentPID, x: 1100), entry(silentPID, x: 1200)], answeredEmpty: [silentPID])
        #expect(selection.owners.isEmpty)
        #expect(selection.multiEntryOwners == [silentPID])
    }

    // MARK: Identity

    @Test
    func `gives the identity an untitled AX child of the same app gets`() throws {
        let synthesized = try #require(DrawnOnlyItems.rawItem(ownerPID: silentPID, app: app, frame: silentFrame))
        let untitled = try #require(MenuBarItemAXProvider.rawItem(
            namespace: .string("com.example.silent"),
            identifier: nil,
            childIdentifier: nil,
            accessibilityDescription: nil,
            childDescription: nil,
            axTitle: nil,
            fallbackIndex: 0,
            bounds: silentFrame,
            ownerPID: silentPID
        ).item)
        let fromDrawn = try #require(MenuBarItemAXProvider.assemble([synthesized]).first)
        let fromAX = try #require(MenuBarItemAXProvider.assemble([untitled]).first)
        #expect(fromDrawn.tag == fromAX.tag)
        #expect(fromDrawn.windowID == fromAX.windowID)
        #expect(fromDrawn.tag.title == "Item-0")
        #expect(fromDrawn.title == "Silent")
        #expect(fromDrawn.windowID == PositionStoreItemSource.syntheticWindowID(
            namespace: .string("com.example.silent"), title: "Item-0", instanceIndex: 0
        ))
    }

    // MARK: Frame

    @Test
    func `takes the vertical band from the median of this pass's own items`() {
        let items = [
            axItem(1, x: 100),
            axItem(2, x: 140),
            RawItem(namespace: .string("a"), identityTitle: "x", displayTitle: "x", bounds: CGRect(x: 180, y: 6, width: 24, height: 18), ownerPID: 3),
            axItem(4, x: 220, namespace: .menuBarAgent).withBounds(CGRect(x: 220, y: 0, width: 30, height: 30)),
        ]
        let band = DrawnOnlyItems.band(of: items)
        #expect(band == DrawnOnlyItems.Band(minY: 4, height: 22))
        let frame = DrawnOnlyItems.normalizedFrame(entry: silentFrame, band: band, ceiling: 40)
        #expect(frame == CGRect(x: 1200, y: 4, width: 30, height: 22))
    }

    @Test
    func `has no band without items outside MenuBarAgent`() {
        #expect(DrawnOnlyItems.band(of: [axItem(4, x: 220, namespace: .menuBarAgent)]) == nil)
    }

    @Test
    func `without a band insets the entry to the ceiling`() {
        #expect(DrawnOnlyItems.normalizedFrame(entry: silentFrame, band: nil, ceiling: 40) == silentFrame)
        let tall = CGRect(x: 1200, y: 0, width: 30, height: 50)
        #expect(DrawnOnlyItems.normalizedFrame(entry: tall, band: nil, ceiling: 40) == CGRect(x: 1200, y: 5, width: 30, height: 40))
    }

    // MARK: Ledger

    @Test
    func `confirms an owner only after it stays drawn and silent for two seconds`() {
        let ledger = DrawnOnlyOwnerLedger()
        let start = ContinuousClock.now
        let first = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start)
        #expect(first.confirmed.isEmpty)
        let early = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start + .seconds(1))
        #expect(early.confirmed.isEmpty)
        let late = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start + .seconds(2))
        #expect(late == DrawnOnlyOwnerLedger.Confirmation(confirmed: [silentPID], newlyConfirmed: [silentPID]))
        let again = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start + .seconds(3))
        #expect(again == DrawnOnlyOwnerLedger.Confirmation(confirmed: [silentPID], newlyConfirmed: []))
    }

    @Test
    func `an owner that publishes through AX starts over`() {
        let ledger = DrawnOnlyOwnerLedger()
        let start = ContinuousClock.now
        _ = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start)
        _ = ledger.confirm(silent: [], answered: [silentPID], running: [silentPID], now: start + .seconds(1))
        #expect(ledger.owners.isEmpty)
        let back = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start + .seconds(2))
        #expect(back.confirmed.isEmpty)
    }

    @Test
    func `an owner that was not asked this pass keeps its place`() {
        let ledger = DrawnOnlyOwnerLedger()
        let start = ContinuousClock.now
        _ = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start)
        _ = ledger.confirm(silent: [], answered: [], running: [silentPID], now: start + .seconds(1))
        let late = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start + .seconds(2))
        #expect(late.confirmed == [silentPID])
    }

    @Test
    func `an owner that quits is dropped`() {
        let ledger = DrawnOnlyOwnerLedger()
        let start = ContinuousClock.now
        _ = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start)
        _ = ledger.confirm(silent: [], answered: [], running: [], now: start + .seconds(1))
        #expect(ledger.owners.isEmpty)
    }

    @Test
    func `reports each skipped owner once`() {
        let ledger = DrawnOnlyOwnerLedger()
        #expect(ledger.firstSkips(of: [silentPID]) == [silentPID])
        #expect(ledger.firstSkips(of: [silentPID]).isEmpty)
    }

    // MARK: Merge

    private var pass: DrawnOnlyItems.Pass {
        DrawnOnlyItems.Pass(apps: [silentPID: app], excluded: [], axItems: [axItem(7, x: 100)], ceiling: 40)
    }

    private func confirmedLedger(now: ContinuousClock.Instant) -> DrawnOnlyOwnerLedger {
        let ledger = DrawnOnlyOwnerLedger()
        _ = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: now - .seconds(3))
        return ledger
    }

    @Test
    func `a settled read replaces the empty answer of a confirmed owner`() throws {
        let now = ContinuousClock.now
        let resolution = DrawnOnlyItems.resolve(
            pending: [silentPID], read: [entry(silentPID, x: 1200)], pass: pass, ledger: confirmedLedger(now: now), now: now
        )
        let item = try #require(DrawnOnlyItems.rawItem(ownerPID: silentPID, app: app, frame: CGRect(x: 1200, y: 4, width: 30, height: 22)))
        #expect(resolution.answers == [silentPID: .record([item])])
        #expect(resolution.newlyConfirmed == [silentPID])
    }

    @Test
    func `an owner not yet confirmed records its empty answer`() {
        let resolution = DrawnOnlyItems.resolve(
            pending: [silentPID], read: [entry(silentPID, x: 1200)], pass: pass, ledger: DrawnOnlyOwnerLedger()
        )
        #expect(resolution.answers == [silentPID: .record([])])
    }

    @Test
    func `a read taken mid-change keeps the prior answer`() {
        let now = ContinuousClock.now
        let ledger = confirmedLedger(now: now)
        let resolution = DrawnOnlyItems.resolve(pending: [silentPID], read: nil, pass: pass, ledger: ledger, now: now)
        #expect(resolution.answers == [silentPID: .keepPrior])
        #expect(ledger.owners == [silentPID])
    }

    @Test
    func `a settled read without the owner records its empty answer`() {
        let now = ContinuousClock.now
        let ledger = confirmedLedger(now: now)
        let resolution = DrawnOnlyItems.resolve(pending: [silentPID], read: [entry(8, x: 900)], pass: pass, ledger: ledger, now: now)
        #expect(resolution.answers == [silentPID: .record([])])
        #expect(ledger.owners.isEmpty)
    }

    @Test
    func `a skipped owner with several entries records its empty answer`() {
        let now = ContinuousClock.now
        let resolution = DrawnOnlyItems.resolve(
            pending: [silentPID],
            read: [entry(silentPID, x: 1100), entry(silentPID, x: 1200)],
            pass: pass,
            ledger: confirmedLedger(now: now),
            now: now
        )
        #expect(resolution.answers == [silentPID: .record([])])
        #expect(resolution.newlySkipped == [silentPID])
    }

    // MARK: Walk

    @Test
    func `the walk waits on drawn owners and on owners the ledger watches`() {
        let inventory = DrawnOnlyInventory()
        #expect(inventory.candidates(drawn: nil).isEmpty)
        #expect(inventory.candidates(drawn: [entry(silentPID, x: 1200), entry(8, x: 900)]) == [silentPID, 8])
    }

    @Test
    func `the walk keeps prior answers when the drawn read is mid-change`() {
        let inventory = DrawnOnlyInventory()
        let answers = inventory.answers(pending: [silentPID], answeredEmpty: [silentPID], read: nil, apps: [:], excluded: [], axItems: [])
        #expect(answers == [silentPID: .keepPrior])
    }

    @Test
    func `the walk records an empty answer for an owner that is not running`() {
        let inventory = DrawnOnlyInventory()
        let answers = inventory.answers(
            pending: [silentPID], answeredEmpty: [silentPID], read: [entry(silentPID, x: 1200)], apps: [:], excluded: [], axItems: []
        )
        #expect(answers == [silentPID: .record([])])
    }

    @Test
    func `the walk has nothing to record when no owner waited`() {
        let inventory = DrawnOnlyInventory()
        #expect(inventory.answers(pending: [], answeredEmpty: [], read: [entry(silentPID, x: 1200)], apps: [:], excluded: [], axItems: []).isEmpty)
    }

    // MARK: Walks without empty answers

    @Test
    func `an inventory with no confirmed owner adds nothing to a helper walk`() {
        let inventory = DrawnOnlyInventory()
        #expect(!inventory.hasConfirmedOwners)
        #expect(inventory.confirmedItems(read: [entry(silentPID, x: 1200)], apps: [:], excluded: [], axItems: []).isEmpty)
        #expect(inventory.confirmedItems(read: nil, apps: [:], excluded: [], axItems: []).isEmpty)
    }

    @Test
    func `the ledger confirms an owner once it has been silent for the delay`() {
        let ledger = DrawnOnlyOwnerLedger()
        let start = ContinuousClock.now
        _ = ledger.confirm(silent: [silentPID], answered: [silentPID], running: [silentPID], now: start)
        #expect(ledger.confirmedOwners(now: start + .seconds(1)).isEmpty)
        #expect(ledger.confirmedOwners(now: start + .seconds(2)) == [silentPID])
    }

    @Test
    func `a walk without empty answers adds the item of a confirmed owner it found nothing for`() throws {
        let items = DrawnOnlyItems.confirmedItems(confirmed: [silentPID], read: [entry(silentPID, x: 1200)], pass: pass)
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.ownerPID == silentPID)
        #expect(item.bounds.minX == 1200)
    }

    @Test
    func `a walk without empty answers adds nothing for an owner it read items for`() {
        let walked = DrawnOnlyItems.Pass(
            apps: [silentPID: app], excluded: [], axItems: [axItem(silentPID, x: 600)], ceiling: 40
        )
        #expect(DrawnOnlyItems.confirmedItems(confirmed: [silentPID], read: [entry(silentPID, x: 1200)], pass: walked).isEmpty)
    }

    @Test
    func `a walk without empty answers adds nothing for unconfirmed, multi-entry or covered owners`() {
        #expect(DrawnOnlyItems.confirmedItems(confirmed: [], read: [entry(silentPID, x: 1200)], pass: pass).isEmpty)
        let twice = [entry(silentPID, x: 1200), entry(silentPID, x: 1240)]
        #expect(DrawnOnlyItems.confirmedItems(confirmed: [silentPID], read: twice, pass: pass).isEmpty)
        let covered = DrawnOnlyItems.Pass(apps: [silentPID: app], excluded: [], axItems: [axItem(7, x: 1203)], ceiling: 40)
        #expect(DrawnOnlyItems.confirmedItems(confirmed: [silentPID], read: [entry(silentPID, x: 1200)], pass: covered).isEmpty)
    }
}

private extension MenuBarItemAXProvider.RawItem {
    func withBounds(_ bounds: CGRect) -> Self {
        Self(namespace: namespace, identityTitle: identityTitle, displayTitle: displayTitle, bounds: bounds, ownerPID: ownerPID)
    }
}
