//
//  CoverageSweep5Tests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Dispatch
import Foundation
import SwiftUI
import Testing
@testable import Thaw

/// Coverage sweep, part 5: the leftover branches in the planner, tag and
/// utility code.
///
/// Covers:
///
/// - `PendingLedger.planPendingMove`'s three unreached destination arms —
///   the fallback-neighbour resolution, the always-hidden section boundary
///   with and without an always-hidden divider, and a `waitForRelaunch`
///   sentinel whose item has not come back yet. `PlanPendingMoveTests`
///   covers the stored-neighbour and hidden-boundary paths.
/// - `MenuBarItemTag(persistenceKey:)` refusing an unknown namespace kind.
///   The persistence key is the on-disk identity of a menu bar item in
///   profiles and in the custom-name store, so its parser has to reject
///   what it does not understand rather than guess a namespace.
/// - `SearchEntry.localizedSection(bundle:)`.
/// - `DispatchQueue.targetingGlobal(label:qos:attributes:)`.
/// - `Permission`'s defaulted `openSettings` parameter.
///
/// Deliberate gaps in the same files: `planPendingMove`'s
/// `guard case let .section` fallthrough and its trailing `.visible` arm are
/// both unreachable — `PendingEntry.Kind` has exactly two cases and the
/// earlier `guard targetSection != .visible` already returned. They are
/// defensive, not dead-by-mistake, so nothing here tries to reach them.
@MainActor
@Suite("Coverage sweep 5: planner, tag and utility residue")
struct CoverageSweep5Tests {
    // MARK: - PendingLedger

    /// Coordinate convention matches `PlanPendingMoveTests`: the hidden
    /// divider sits at x=400 width 10, so an item at x>=410 is "visible" and
    /// still needs relocating.
    @MainActor
    @Suite("PendingLedger destination fallbacks")
    struct PendingLedgerTests {
        private let hiddenBounds = CGRect(x: 400, y: 0, width: 10, height: 22)

        private func visibleItem(title: String, windowID: CGWindowID, x: CGFloat = 500) -> MenuBarItem {
            MenuBarItem.fixture(
                tag: .appItem(bundleID: "com.example.app", title: title),
                windowID: windowID,
                bounds: CGRect(x: x, y: 0, width: 24, height: 22)
            )
        }

        private func plan(
            entry: PendingLedger.PendingEntry,
            items: [MenuBarItem],
            controlItems: MenuBarItemManager.ControlItemPair,
            returnInfo: PendingLedger.PendingReturnInfo = PendingLedger.PendingReturnInfo(
                destinations: [:],
                fallbackNeighbors: [:]
            )
        ) -> PendingLedger.PendingMove {
            PendingLedger.planPendingMove(
                entry: entry,
                items: items,
                controlItems: controlItems,
                hiddenBounds: hiddenBounds,
                boundsForWindowID: [:],
                activelyShownTags: [],
                returnInfo: returnInfo
            )
        }

        /// The sentinel exists precisely because the owning app quit. Until
        /// it relaunches there is no item to compare window IDs against, and
        /// the entry has to survive to the next pass rather than be cleared.
        @Test("A waitForRelaunch sentinel whose item is still gone skips")
        func waitForRelaunchWithAbsentItemSkips() {
            let entry = PendingLedger.PendingEntry(
                tagIdentifier: "com.example.app:Status",
                kind: .waitForRelaunch(windowID: 900, section: .hidden)
            )

            let decision = plan(
                entry: entry,
                items: [],
                controlItems: .fixture(hiddenAt: hiddenBounds)
            )

            #expect(decision == .skip(reason: .itemNotPresent))
        }

        /// With no stored destination, the live nearest-neighbour cache is
        /// consulted before the section boundary — and always to the *right*
        /// of that neighbour.
        @Test("A fallback neighbour is used when no destination was stored")
        func fallbackNeighbourIsUsedWhenNoDestinationWasStored() {
            let item = visibleItem(title: "Status", windowID: 910)
            let neighbor = visibleItem(title: "Neighbour", windowID: 911, x: 600)
            let entry = PendingLedger.PendingEntry(
                tagIdentifier: item.tag.tagIdentifier,
                kind: .section(.hidden)
            )

            let decision = plan(
                entry: entry,
                items: [item, neighbor],
                controlItems: .fixture(hiddenAt: hiddenBounds),
                returnInfo: PendingLedger.PendingReturnInfo(
                    destinations: [:],
                    fallbackNeighbors: [item.tag.tagIdentifier: neighbor.tag]
                )
            )

            guard case let .move(movedItem, destination) = decision else {
                Issue.record("expected .move, got \(decision)")
                return
            }
            #expect(movedItem.windowID == 910)
            guard case let .rightOfItem(target) = destination else {
                Issue.record("expected .rightOfItem, got \(destination)")
                return
            }
            #expect(target.windowID == 911)
        }

        /// A fallback neighbour that is no longer in the live item list is
        /// stale; the planner must fall through to the section boundary
        /// instead of aiming at an item that is not there.
        @Test("A fallback neighbour that is no longer present falls through to the boundary")
        func staleFallbackNeighbourFallsThroughToTheBoundary() {
            let item = visibleItem(title: "Status", windowID: 912)
            let departed = visibleItem(title: "Departed", windowID: 913, x: 600)
            let entry = PendingLedger.PendingEntry(
                tagIdentifier: item.tag.tagIdentifier,
                kind: .section(.hidden)
            )

            let decision = plan(
                entry: entry,
                items: [item],
                controlItems: .fixture(hiddenAt: hiddenBounds),
                returnInfo: PendingLedger.PendingReturnInfo(
                    destinations: [:],
                    fallbackNeighbors: [item.tag.tagIdentifier: departed.tag]
                )
            )

            guard case let .move(_, destination) = decision,
                  case let .leftOfItem(target) = destination
            else {
                Issue.record("expected .move(.leftOfItem), got \(decision)")
                return
            }
            #expect(target.tag == .hiddenControlItem)
        }

        @Test("An always-hidden entry lands left of the always-hidden divider")
        func alwaysHiddenEntryLandsLeftOfTheAlwaysHiddenDivider() {
            let item = visibleItem(title: "Status", windowID: 914)
            let entry = PendingLedger.PendingEntry(
                tagIdentifier: item.tag.tagIdentifier,
                kind: .section(.alwaysHidden)
            )

            let decision = plan(
                entry: entry,
                items: [item],
                controlItems: .fixture(
                    hiddenAt: hiddenBounds,
                    alwaysHiddenAt: CGRect(x: 100, y: 0, width: 10, height: 22)
                )
            )

            guard case let .move(_, destination) = decision,
                  case let .leftOfItem(target) = destination
            else {
                Issue.record("expected .move(.leftOfItem), got \(decision)")
                return
            }
            #expect(target.tag == .alwaysHiddenControlItem)
        }

        /// The always-hidden section can be switched off, which removes its
        /// divider. An entry recorded before that must degrade to the hidden
        /// divider rather than be dropped.
        @Test("An always-hidden entry degrades to the hidden divider when the section is off")
        func alwaysHiddenEntryDegradesWhenTheSectionIsOff() {
            let item = visibleItem(title: "Status", windowID: 915)
            let entry = PendingLedger.PendingEntry(
                tagIdentifier: item.tag.tagIdentifier,
                kind: .section(.alwaysHidden)
            )

            let decision = plan(
                entry: entry,
                items: [item],
                controlItems: .fixture(hiddenAt: hiddenBounds)
            )

            guard case let .move(_, destination) = decision,
                  case let .leftOfItem(target) = destination
            else {
                Issue.record("expected .move(.leftOfItem), got \(decision)")
                return
            }
            #expect(target.tag == .hiddenControlItem)
        }
    }

    // MARK: - MenuBarItemTag

    @MainActor
    @Suite("MenuBarItemTag persistence key parsing")
    struct TagParsingTests {
        /// The three kinds are the stored format. Anything else is either a
        /// key written by a newer build or a corrupted one, and either way
        /// guessing a namespace would file the item under an identity that
        /// is not its own.
        @Test(
            "An unknown namespace kind is rejected",
            arguments: ["z:com.example.app:0:Status", "N:com.example.app:0:Status", ":com.example.app:0:Status"]
        )
        func unknownNamespaceKindIsRejected(_ persistenceKey: String) {
            #expect(MenuBarItemTag(persistenceKey: persistenceKey) == nil)
        }

        @Test("The three known kinds are accepted")
        func knownNamespaceKindsAreAccepted() throws {
            let uuid = UUID()
            let null = try #require(MenuBarItemTag(persistenceKey: "n::0:Status"))
            let string = try #require(MenuBarItemTag(persistenceKey: "s:com.example.app:0:Status"))
            let uuidTag = try #require(MenuBarItemTag(persistenceKey: "u:\(uuid.uuidString):0:Status"))

            #expect(null.namespace == .null)
            #expect(string.namespace == .string("com.example.app"))
            #expect(uuidTag.namespace == .uuid(uuid))
        }

        @Test("A malformed UUID namespace is rejected")
        func malformedUUIDNamespaceIsRejected() {
            #expect(MenuBarItemTag(persistenceKey: "u:not-a-uuid:0:Status") == nil)
        }

        @Test("A non-numeric instance index is rejected")
        func nonNumericInstanceIndexIsRejected() {
            #expect(MenuBarItemTag(persistenceKey: "s:com.example.app:first:Status") == nil)
        }
    }

    // MARK: - SearchEntry

    @MainActor
    @Suite("Search entry section headers")
    struct SearchEntrySectionTests {
        /// `String(localized:)` picks its localization from the bundle, not
        /// from a `locale:` argument, so resolving against a specific
        /// `.lproj` is the only way to pin the lookup in-process.
        private static func localizationBundle(_ identifier: String) throws -> Bundle {
            let path = try #require(Bundle.main.path(forResource: identifier, ofType: "lproj"))
            return try #require(Bundle(path: path))
        }

        @Test("A sectioned entry resolves its header through the catalog")
        func sectionedEntryResolvesItsHeader() throws {
            let entry = try #require(SearchIndex.entries.first { $0.id == "general.showOnClick" })
            let english = try Self.localizationBundle("en")

            #expect(entry.sectionText == "Empty menu bar area")
            // The English source doubles as the catalog key, so resolving
            // against `en` has to give the source string back.
            #expect(entry.localizedSection(bundle: english) == "Empty menu bar area")
        }

        @Test("An entry without a section header resolves to nil")
        func unsectionedEntryResolvesToNil() throws {
            let entry = try #require(SearchIndex.entries.first { $0.id == "pane.general" })

            #expect(entry.sectionText == nil)
            #expect(entry.localizedSection() == nil)
        }

        @Test("Every entry that has a section header can resolve it")
        func everySectionedEntryResolves() throws {
            let english = try Self.localizationBundle("en")
            let sectioned = SearchIndex.entries.filter { $0.sectionText != nil }

            #expect(!sectioned.isEmpty)
            for entry in sectioned {
                #expect(entry.localizedSection(bundle: english) == entry.sectionText)
            }
        }
    }

    // MARK: - DispatchQueue

    @MainActor
    @Suite("Global-targeting dispatch queues")
    struct DispatchQueueTests {
        @Test("The queue keeps the label it was given and runs work")
        func targetingGlobalKeepsItsLabel() {
            let queue = DispatchQueue.targetingGlobal(label: "com.stonerl.ThawTests.sweep")

            #expect(queue.label == "com.stonerl.ThawTests.sweep")
            #expect(queue.sync { 6 * 7 } == 42)
        }

        @Test("The explicit quality-of-service and attribute overloads are usable")
        func targetingGlobalAcceptsQoSAndAttributes() {
            let queue = DispatchQueue.targetingGlobal(
                label: "com.stonerl.ThawTests.sweep.concurrent",
                qos: .utility,
                attributes: .concurrent
            )
            var total = 0

            queue.sync(flags: .barrier) { total += 1 }
            queue.sync(flags: .barrier) { total += 1 }

            #expect(queue.label == "com.stonerl.ThawTests.sweep.concurrent")
            #expect(total == 2)
        }
    }

    // MARK: - Permission

    @MainActor
    @Suite("Permission defaults")
    struct PermissionDefaultsTests {
        /// Constructed without `openSettings`, so the default closure — the
        /// one that hands the URL to `NSWorkspace` — is what gets stored.
        /// `settingsURL` is `nil` so `performRequest` exercises the
        /// no-URL arm and nothing is ever actually opened.
        @Test("A permission built without an opener still requests and polls")
        func defaultOpenSettingsIsInstalled() {
            var isGranted = false
            var requestCount = 0
            let permission = Permission(
                title: "Sweep Permission",
                iconName: "checkmark",
                iconColor: .blue,
                details: ["only used by the test suite"],
                isRequired: false,
                settingsURL: nil,
                check: { isGranted },
                request: { requestCount += 1 }
            )
            defer { permission.stopCheck() }

            #expect(!permission.hasPermission)

            isGranted = true
            permission.performRequest()

            #expect(requestCount == 1)
            // `performRequest` restarts polling, and the restart's first tick
            // is delivered synchronously, so the grant is already visible.
            #expect(permission.hasPermission)
        }

        @Test("A permission records the details it was built with")
        func permissionKeepsItsDescriptiveFields() {
            let permission = Permission(
                title: "Sweep Permission",
                iconName: "record.circle",
                iconColor: .red,
                details: ["first", "second"],
                isRequired: true,
                settingsURL: nil,
                check: { true },
                request: {}
            )
            defer { permission.stopCheck() }

            #expect(permission.title == "Sweep Permission")
            #expect(permission.iconName == "record.circle")
            #expect(permission.iconColor == Color.red)
            #expect(permission.details == ["first", "second"])
            #expect(permission.isRequired)
            #expect(permission.hasPermission)
        }
    }
}
