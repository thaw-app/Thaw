//
//  DynamicMetricTitleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// Live metric titles need canonical identities across builds, including Setapp, to avoid saved-layout churn.
@Suite("Dynamic metric titles")
struct DynamicMetricTitleTests {
    @Test("Amphetamine's reported titles share one live and persisted identity", arguments: ["Item-0", "∞", "𝗧"])
    func amphetamineTitlesShareIdentity(_ title: String) {
        let bundleID = "com.if.Amphetamine"
        let tag = MenuBarItemTag(namespace: .string(bundleID), title: title)
        #expect(tag.tagIdentifier == "\(bundleID):Item")
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundleID):\(title)") == tag.tagIdentifier)
    }

    @Test("Amphetamine canonicalization preserves distinct instance indices")
    func amphetamineInstancesStayDistinct() {
        let bundleID = "com.if.Amphetamine"
        let first = MenuBarItemTag(namespace: .string(bundleID), title: "∞", instanceIndex: 0)
        let second = MenuBarItemTag(namespace: .string(bundleID), title: "𝗧", instanceIndex: 1)
        #expect(first.tagIdentifier != second.tagIdentifier)
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundleID):𝗧:1") == second.tagIdentifier)
        #expect(MenuBarItemTag.canonicalPersistentIdentifiers([
            "\(bundleID):Item-0", "\(bundleID):∞", "\(bundleID):𝗧", "\(bundleID):𝗧:1",
        ]) == [first.tagIdentifier, second.tagIdentifier])
    }

    @Test("The Amphetamine rule does not match other bundle IDs")
    func amphetamineRuleMatchesExactBundle() {
        #expect(MenuBarItemTag.hasVolatileTitles("com.if.Amphetamine"))
        #expect(!MenuBarItemTag.hasVolatileTitles("com.if.Amphetamine.helper"))
        #expect(!MenuBarItemTag.hasVolatileTitles("com.if.AmphetamineOther"))
    }

    // MARK: Learned owners

    @Test("A learned owner's titles collapse like Dato's")
    func learnedOwnerCollapsesTitles() {
        // A bundle no other test touches: the learned set is process-wide.
        let bundleID = "test.learned.RetitlingApp"
        defer { MenuBarItemTag.restoreLearnedVolatileTitleOwners([]) }
        #expect(!MenuBarItemTag.hasVolatileTitles(bundleID))
        #expect(MenuBarItemTag.learnVolatileTitleOwner(bundleID))
        #expect(!MenuBarItemTag.learnVolatileTitleOwner(bundleID))
        #expect(MenuBarItemTag.hasVolatileTitles(bundleID))
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("\(bundleID):3 unread:0") == "\(bundleID):Item:0")
    }

    @Test("An owner another rule already covers is not learned")
    func coveredOwnerIsNotLearned() {
        #expect(!MenuBarItemTag.learnVolatileTitleOwner("eu.exelban.Stats"))
        #expect(!MenuBarItemTag.learnedVolatileTitleOwners.contains("eu.exelban.Stats"))
    }

    // MARK: Bundle matching

    @Test("iStat Menus is matched across its distribution builds")
    func matchesEveryIStatBuild() {
        #expect(MenuBarItemTag.hasDynamicMetricTitles("com.bjango.istatmenus.status"))
        #expect(MenuBarItemTag.hasDynamicMetricTitles("com.bjango.istatmenus-setapp.status"))
        #expect(MenuBarItemTag.hasDynamicMetricTitles(MenuBarItemTag.iStatMenusStatusBundleID))
    }

    @Test("Stats is matched")
    func matchesStats() {
        #expect(MenuBarItemTag.hasDynamicMetricTitles("eu.exelban.Stats"))
    }

    @Test("The main iStat app is not the status helper")
    func doesNotMatchMainIStatApp() {
        // Only the .status helper owns menu bar items; the main app must not
        // have its titles rewritten.
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("com.bjango.istatmenus"))
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("com.bjango.istatmenus-setapp"))
    }

    @Test("Unrelated bundles are untouched")
    func doesNotMatchUnrelatedBundles() {
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("com.example.app"))
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("eu.exelban.SomethingElse"))
        #expect(!MenuBarItemTag.hasDynamicMetricTitles(""))
    }

    // MARK: Identifier canonicalization

    @Test("A Setapp iStat identifier canonicalizes, so metric ticks share one identity")
    func setappIdentifierCanonicalizes() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        let first = MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):CPU 42%")
        let second = MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):CPU 43%")

        #expect(first == second)
        #expect(first == "\(bundle):CPU #%")
    }

    @Test("Numeric churn inside a battery title collapses to one identity")
    func batteryNumericChurnCollapses() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        let monday = "\(bundle):Battery: 100%, Charged. AirPods Pro: 0%."
        let tuesday = "\(bundle):Battery: 87%, Charged. AirPods Pro: 45%."

        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier(monday)
                == MenuBarItemTag.canonicalPersistentIdentifier(tuesday)
        )
    }

    /// Module names avoid identity churn from localized charge-state words and peripheral changes that digit rules miss.
    @Test("Non-numeric churn in a battery title collapses to the module name")
    func batteryWordChurnCollapsesToModule() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        let charged = "\(bundle):Battery: 100%, Charged. Magic Trackpad: 100%. AirPods Pro: 0%."
        let charging = "\(bundle):Battery: 87%, Charging. AirPods Pro: 45%."
        let alone = "\(bundle):Battery: 5%, Discharging."

        #expect(MenuBarItemTag.canonicalPersistentIdentifier(charged) == "\(bundle):Battery")
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier(charged)
                == MenuBarItemTag.canonicalPersistentIdentifier(charging)
        )
        // A peripheral disconnecting entirely must not change identity either.
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier(charged)
                == MenuBarItemTag.canonicalPersistentIdentifier(alone)
        )
    }

    @Test("Different modules keep different identities")
    func differentModulesStayDistinct() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Battery: 100%, Charged.")
                != MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Disks: 45% used.")
        )
    }

    @Test("A genuine instance suffix survives module truncation")
    func instanceSurvivesModuleTruncation() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Battery: 100%, Charged.:1")
                == "\(bundle):Battery:1"
        )
    }

    @Test("Titles with no module prefix still fall back to neutralizing numbers")
    func titlesWithoutModulePrefixUseDigitRule() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):Upload 15.3 KB/s, Download 1.2 MB/s")
                == "\(bundle):Upload # B/s, Download # B/s"
        )
        // A bare clock has no ": " separator, so it takes the digit rule.
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):15:41")
                == MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):15:42")
        )
    }

    @Test("An instance suffix survives canonicalization")
    func instanceSuffixPreserved() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):CPU 42%:1")
                == "\(bundle):CPU #%:1"
        )
    }

    @Test("Distinct gauges stay distinct")
    func distinctGaugesStayDistinct() {
        let bundle = "com.bjango.istatmenus-setapp.status"
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):CPU 42%")
                != MenuBarItemTag.canonicalPersistentIdentifier("\(bundle):MEM 42%")
        )
    }

    @Test("Unrelated identifiers pass through untouched")
    func unrelatedIdentifiersUntouched() {
        #expect(
            MenuBarItemTag.canonicalPersistentIdentifier("com.example.app:Item-0")
                == "com.example.app:Item-0"
        )
        // A bare identifier with no namespace separator must not trap.
        #expect(MenuBarItemTag.canonicalPersistentIdentifier("bare") == "bare")
    }

    // MARK: Title canonicalization

    @Test("canonicalTitle follows the same family rule as identifiers")
    func canonicalTitleMatchesFamily() {
        #expect(
            MenuBarItemTag.canonicalTitle(
                namespace: .string("com.bjango.istatmenus-setapp.status"),
                title: "CPU 42%"
            ) == "CPU #%"
        )
        #expect(
            MenuBarItemTag.canonicalTitle(namespace: .string("com.example.app"), title: "CPU 42%")
                == "CPU 42%"
        )
        // Non-string namespaces have no bundle ID to match.
        #expect(MenuBarItemTag.canonicalTitle(namespace: .menuBarAgent, title: "42") == "42")
    }

    @Test("Tag identity is stable across metric ticks for a Setapp gauge")
    func tagIdentityStableAcrossTicks() {
        func tag(_ title: String) -> MenuBarItemTag {
            MenuBarItemTag(
                namespace: .string("com.bjango.istatmenus-setapp.status"),
                title: title,
                windowID: nil,
                instanceIndex: 0
            )
        }

        #expect(tag("CPU 42%").tagIdentifier == tag("CPU 43%").tagIdentifier)
    }

    // MARK: Countdown-prefix titles

    @Test("Outlook is matched, its helper bundles included")
    func matchesOutlook() {
        #expect(MenuBarItemTag.hasCountdownPrefixTitles("com.microsoft.Outlook"))
        // The metric rule would keep Outlook's volatile countdown before ": ".
        #expect(!MenuBarItemTag.hasDynamicMetricTitles("com.microsoft.Outlook"))
    }

    @Test("A counting-down meeting keeps one identity")
    func countdownCollapsesToTheMeetingName() {
        func tag(_ title: String) -> MenuBarItemTag {
            MenuBarItemTag(
                namespace: .string("com.microsoft.Outlook"),
                title: title,
                windowID: nil,
                instanceIndex: 0
            )
        }

        let meeting = "Florida and Advent Daily Reconciliation Meeting"
        let identifiers = Set(
            ["17m:  ", "9m:  ", "8m:  ", "7m:  ", "Now:  "]
                .map { tag($0 + meeting).tagIdentifier }
        )
        #expect(identifiers == ["com.microsoft.Outlook:\(meeting)"])
    }

    @Test("Different meetings stay different items")
    func differentMeetingsStayDistinct() {
        #expect(
            MenuBarItemTag.canonicalCountdownPrefixTitle("7m:  Team sync")
                != MenuBarItemTag.canonicalCountdownPrefixTitle("7m:  Standup")
        )
    }

    @Test("A title with nothing behind the countdown is left alone")
    func emptyRemainderPassesThrough() {
        #expect(MenuBarItemTag.canonicalCountdownPrefixTitle("No meetings") == "No meetings")
        #expect(MenuBarItemTag.canonicalCountdownPrefixTitle("Now:  ") == "Now:  ")
    }

    @Test("Stored Outlook identifiers canonicalize the same way")
    func persistentIdentifiersCanonicalize() {
        let canonical = MenuBarItemTag.canonicalPersistentIdentifiers([
            "com.microsoft.Outlook:17m:  Team sync",
            "com.microsoft.Outlook:Now:  Team sync",
        ])
        #expect(canonical == ["com.microsoft.Outlook:Team sync"])
    }
}
