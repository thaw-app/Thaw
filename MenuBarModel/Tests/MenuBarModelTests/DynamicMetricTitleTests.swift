//
//  DynamicMetricTitleTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
@testable import MenuBarModel
import Testing

/// Apps that write live metric values into their status-item titles need those
/// titles canonicalized before the title can serve as identity. Matching one
/// literal bundle ID missed iStat Menus' Setapp build entirely, so every metric
/// tick minted a fresh identifier and churned the user's saved layout.
@Suite("Dynamic metric titles")
struct DynamicMetricTitleTests {
    // MARK: Bundle matching

    @Test("iStat Menus is matched across its distribution builds")
    func matchesEveryIStatBuild() {
        #expect(MenuBarItemTag.hasDynamicMetricTitles("com.bjango.istatmenus.status"))
        #expect(MenuBarItemTag.hasDynamicMetricTitles("com.bjango.istatmenus-setapp.status"))
        // The documented constant must itself still match.
        #expect(MenuBarItemTag.hasDynamicMetricTitles(MenuBarItemTag.iStatMenusStatusBundleID))
    }

    @Test("Stats is matched")
    func matchesStats() {
        #expect(MenuBarItemTag.hasDynamicMetricTitles("eu.exelban.Stats"))
    }

    @Test("The main iStat app is not the status helper")
    func doesNotMatchMainIStatApp() {
        // Only the `.status` helper owns menu bar items; the main app must not
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

    /// The failure behind the original report: a digit-only rule cannot catch
    /// "Charged" → "Charging", nor a peripheral appearing or disappearing, so
    /// the battery gauge minted a fresh identity and fell out of saved layouts.
    /// Keying on the module name fixes it without needing a localized word list.
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
}
