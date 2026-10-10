//
//  VolatileTitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// Dato's clock and meeting countdown have no stable title fragment.
/// Raw ticks create new identities, losing stored positions and sending items back to hidden.
@Suite("Volatile titles")
struct VolatileTitleTests {
    private static let dato = MenuBarItemTag.Namespace.string("com.sindresorhus.Dato")

    private static func tag(_ title: String, instanceIndex: Int = 0) -> MenuBarItemTag {
        MenuBarItemTag(namespace: dato, title: title, instanceIndex: instanceIndex)
    }

    // MARK: Bundle matching

    @Test("MacThrottle keeps one identity across temperature ticks and display modes")
    func macThrottleKeepsOneIdentity() {
        let namespace = MenuBarItemTag.Namespace.string("com.macthrottle.app")
        let titles = ["64°", "66°", "Item-0", "thermometer.low", "thermometer.high"]
        let identifiers = titles.map {
            MenuBarItemTag(namespace: namespace, title: $0).tagIdentifier
        }
        #expect(Set(identifiers).count == 1)
        #expect(MenuBarItemTag.hasCanonicalizableTitles("com.macthrottle.app"))
    }

    @Test("MacThrottle's saved temperature entries collapse into one item")
    func macThrottleSavedEntriesDeduplicate() {
        #expect(MenuBarItemTag.canonicalPersistentIdentifiers([
            "com.macthrottle.app:64°",
            "com.macthrottle.app:66°",
            "com.macthrottle.app:Item-0",
        ]) == ["com.macthrottle.app:Item"])
    }

    @Test("Dato is matched")
    func matchesDato() {
        #expect(MenuBarItemTag.hasVolatileTitles("com.sindresorhus.Dato"))
    }

    @Test("ThermalForge is matched")
    func matchesThermalForge() {
        // ThermalForge renders the live temperature as the entire title ("66°"),
        // so the whole title is volatile and must collapse to the placeholder.
        #expect(MenuBarItemTag.hasVolatileTitles("com.thermalforge.app"))
    }

    @Test("Another app from the same developer is untouched")
    func doesNotMatchSiblingApps() {
        // A developer-wide match would collapse Googly Eyes' stable title too.
        #expect(!MenuBarItemTag.hasVolatileTitles("com.sindresorhus.Googly-Eyes"))
        #expect(!MenuBarItemTag.hasVolatileTitles("com.raycast.macos"))
    }

    @Test("The volatile family is separate from the metric and countdown ones")
    func familiesDoNotOverlap() {
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("com.sindresorhus.Dato"))
        #expect(!MenuBarItemTag.hasCountdownPrefixTitles("com.sindresorhus.Dato"))
        #expect(!MenuBarItemTag.hasVolatileTitles("com.bjango.istatmenus.status"))
        #expect(!MenuBarItemTag.hasVolatileTitles("com.microsoft.Outlook"))
    }

    @Test("ThermalForge is not mistaken for a metric or countdown title")
    func thermalForgeIsNotMetricOrCountdown() {
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("com.thermalforge.app"))
        #expect(!MenuBarItemTag.hasCountdownPrefixTitles("com.thermalforge.app"))
        #expect(!MenuBarItemTag.hasMultilineStatusTitles("com.thermalforge.app"))
    }

    @Test("Every canonicalizable family answers the shared predicate")
    func sharedPredicateCoversEveryFamily() {
        // The AX provider uses the shared predicate to cover Setapp iStat and Stats too.
        #expect(MenuBarItemTag.hasCanonicalizableTitles("com.sindresorhus.Dato"))
        #expect(MenuBarItemTag.hasCanonicalizableTitles("com.bjango.istatmenus-setapp.status"))
        #expect(MenuBarItemTag.hasCanonicalizableTitles("eu.exelban.Stats"))
        #expect(MenuBarItemTag.hasCanonicalizableTitles("com.microsoft.Outlook"))
        #expect(!MenuBarItemTag.hasCanonicalizableTitles("com.raycast.macos"))
    }

    // MARK: Collapsing

    @Test("Successive clock titles collapse to one identity")
    func clockTicksShareOneIdentity() {
        let earlier = Self.tag("Mon 7 Sep  10:53 AM")
        let later = Self.tag("Mon 7 Sep  10:54 AM")
        #expect(earlier.canonicalTitle == later.canonicalTitle)
        #expect(earlier.tagIdentifier == later.tagIdentifier)
    }

    @Test("A date rollover does not mint a new identity either")
    func dateRolloverSharesOneIdentity() {
        // Stripping digits alone leaves weekday names to churn once a day.
        #expect(Self.tag("Mon 7 Sep  11:59 PM").tagIdentifier
            == Self.tag("Tue 8 Sep  12:00 AM").tagIdentifier)
    }

    @Test("A counting-down event collapses onto the same placeholder")
    func eventTitlesCollapse() {
        #expect(Self.tag("Declined: Prepare f… in 6m").canonicalTitle
            == MenuBarItemTag.volatileTitlePlaceholder)
        #expect(Self.tag("Mon 7 Sep  10:54 AM").canonicalTitle
            == MenuBarItemTag.volatileTitlePlaceholder)
    }

    // MARK: Custom date formats

    @Test("Any custom format collapses to the same identity")
    func arbitraryCustomFormatsShareOneIdentity() {
        // A saved layout must survive switching date formats, so none of these
        // may mint an identity apart from the default's.
        let formats = [
            "Mon 7 Sep  10:54 AM", // default
            "21", // day number only
            "10:54",
            "10:54:33", // ticking seconds
            "21 Sep",
            "2026-09-21", // ISO date
            "09/21/2026", // slash date
            "📅 Sun 21 Sep", // emoji prefix
            "Sun 21 Sep EEST", // timezone suffix
            "Item-0", // no-title fallback while the app launches
            "",
        ]
        let identifiers = formats.map { Self.tag($0).tagIdentifier }
        #expect(Set(identifiers).count == 1)
    }

    @Test("A stored identifier from any format canonicalizes to the placeholder")
    func storedIdentifiersFromAnyFormatCanonicalize() {
        // The colon inside a time format must not be mistaken for an instance
        // suffix, whichever position it lands in.
        let stored = ["21", "10:54", "2026-09-21 10:54", "📅 Sun 21 Sep"].map {
            MenuBarItemTag.canonicalPersistentIdentifier("com.sindresorhus.Dato:\($0)")
        }
        #expect(Set(stored) == ["com.sindresorhus.Dato:Item"])
    }

    @Test("The two items stay distinct through their instance index")
    func siblingsRemainDistinct() {
        // Both titles collapse, so position is the only thing left telling the
        // clock item from the next-event item.
        let clock = Self.tag("Mon 7 Sep  10:54 AM", instanceIndex: 0)
        let event = Self.tag("Declined: Prepare f… in 6m", instanceIndex: 1)
        #expect(clock.tagIdentifier != event.tagIdentifier)
        #expect(event.tagIdentifier.hasSuffix(":1"))
    }

    @Test("An identity survives a tick on both items at once")
    func bothItemsSurviveATick() {
        #expect(Self.tag("Mon 7 Sep  10:53 AM", instanceIndex: 0).tagIdentifier
            == Self.tag("Mon 7 Sep  10:54 AM", instanceIndex: 0).tagIdentifier)
        #expect(Self.tag("Declined: Prepare f… in 6m", instanceIndex: 1).tagIdentifier
            == Self.tag("Declined: Prepare f… in 5m", instanceIndex: 1).tagIdentifier)
    }

    // MARK: Persisted identifiers

    @Test("A stored clock identifier canonicalizes to the placeholder")
    func storedIdentifierCanonicalizes() {
        // The colon inside "10:53" must not be mistaken for an instance suffix.
        #expect(MenuBarItemTag.canonicalPersistentIdentifier(
            "com.sindresorhus.Dato:Mon 7 Sep  10:53 AM"
        ) == "com.sindresorhus.Dato:Item")
    }

    @Test("A stored identifier keeps its instance suffix")
    func storedInstanceSuffixSurvives() {
        #expect(MenuBarItemTag.canonicalPersistentIdentifier(
            "com.sindresorhus.Dato:Declined: Prepare f… in 6m:1"
        ) == "com.sindresorhus.Dato:Item:1")
    }

    @Test("A run of stored identifiers collapses to one per item")
    func storedIdentifiersDeduplicate() {
        let collapsed = MenuBarItemTag.canonicalPersistentIdentifiers([
            "com.sindresorhus.Dato:Mon 7 Sep  10:53 AM",
            "com.sindresorhus.Dato:Mon 7 Sep  10:54 AM",
            "com.sindresorhus.Dato:Mon 7 Sep  10:55 AM",
        ])
        #expect(collapsed == ["com.sindresorhus.Dato:Item"])
    }

    // MARK: Interaction with generic-title handling

    @Test("The placeholder is not a generic untitled-item name")
    func placeholderIsNotAGenericTitle() {
        // Owner-scoped reveal fallback is for untitled items, not Dato's unstable titles.
        #expect(!MenuBarItemTag.isGenericItemTitle(
            MenuBarItemTag.volatileTitlePlaceholder
        ))
    }

    // MARK: ThermalForge collapsing

    @Test("Successive ThermalForge temperature readings collapse to one identity")
    func thermalForgeReadingsShareOneIdentity() {
        let bundle = "com.thermalforge.app"
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):64°")
            == MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):66°"))
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):66°")
            == "\(bundle):Item")
    }

    @Test("The no-title fallback collapses to the same ThermalForge identity")
    func thermalForgeNoTitleFallbackCollapses() {
        // The startup "Item-0" title must share the live reading's identity to avoid duplicate layout entries.
        let bundle = "com.thermalforge.app"
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Item-0")
            == MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):66°"))
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Item-0")
            == "\(bundle):Item")
    }

    // MARK: Multi-line status titles

    @Test("OneDrive is matched, and as a separate family from Dato")
    func matchesOneDrive() {
        #expect(MenuBarItemTag.hasMultilineStatusTitles("com.microsoft.OneDrive"))
        #expect(!MenuBarItemTag.hasVolatileTitles("com.microsoft.OneDrive"))
        #expect(!MenuBarItemTag.hasMultilineStatusTitles("com.sindresorhus.Dato"))
        #expect(MenuBarItemTag.hasCanonicalizableTitles("com.microsoft.OneDrive"))
    }

    @Test("A changing sync state does not mint a new identity")
    func syncStateChurnSharesOneIdentity() {
        let synced = MenuBarItemTag(
            namespace: .string("com.microsoft.OneDrive"),
            title: "OneDrive — Personal\nBacked up and synced"
        )
        let syncing = MenuBarItemTag(
            namespace: .string("com.microsoft.OneDrive"),
            title: "OneDrive — Personal\nSyncing 3 items"
        )
        #expect(synced.tagIdentifier == syncing.tagIdentifier)
        #expect(synced.canonicalTitle == "OneDrive — Personal")
    }

    @Test("Two accounts stay distinct rather than collapsing onto one identity")
    func accountsRemainDistinct() {
        // Collapsing the whole title would leave only the instance index to distinguish two tenants.
        let personal = MenuBarItemTag(
            namespace: .string("com.microsoft.OneDrive"),
            title: "OneDrive — Personal\nBacked up and synced"
        )
        let work = MenuBarItemTag(
            namespace: .string("com.microsoft.OneDrive"),
            title: "OneDrive —  WWF\nBacked up and synced"
        )
        #expect(personal.tagIdentifier != work.tagIdentifier)
        #expect(work.canonicalTitle == "OneDrive —  WWF")
    }

    @Test("The canonical title matches the key the host stores")
    func canonicalTitleMatchesHostKey() {
        // The agent keys on the first line alone, so this is the string the
        // position store has to build its key from.
        let tag = MenuBarItemTag(
            namespace: .string("com.microsoft.OneDrive"),
            title: "OneDrive — Personal\nBacked up and synced"
        )
        #expect("status:com.microsoft.OneDrive::\(tag.canonicalTitle)"
            == "status:com.microsoft.OneDrive::OneDrive — Personal")
    }

    @Test("A single-line title is unchanged")
    func singleLineTitleIsUntouched() {
        #expect(MenuBarItemTag.canonicalFirstLineTitle("OneDrive — Personal")
            == "OneDrive — Personal")
    }

    @Test("A title that leads with a newline falls back to the raw string")
    func leadingNewlineFallsBack() {
        // Otherwise every such item would share one empty identity.
        #expect(MenuBarItemTag.canonicalFirstLineTitle("\nBacked up and synced")
            == "\nBacked up and synced")
    }

    @Test("Stored OneDrive identifiers canonicalize the same way")
    func storedOneDriveIdentifierCanonicalizes() {
        #expect(MenuBarItemTag.canonicalPersistentIdentifier(
            "com.microsoft.OneDrive:OneDrive — Personal\nBacked up and synced"
        ) == "com.microsoft.OneDrive:OneDrive — Personal")
    }

    @Test("Unrelated apps keep their titles verbatim")
    func unrelatedTitlesPassThrough() {
        let raycast = MenuBarItemTag(namespace: .string("com.raycast.macos"), title: "Item-0")
        #expect(raycast.canonicalTitle == "Item-0")
    }
}
