//
//  MarkerPairResolverTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Characterization tests for MarkerPairResolver, the helper that
/// pairs unresolved on-screen icons with bundle-ID-titled marker
/// windows and resolves them to a sourcePID via injected lookups.
///
/// Covers the macOS 26 marker-pair workflow used by SourcePIDCache
/// when the spatial AX pass cannot reach a widget's own
/// AXExtrasMenuBar.
@Suite("Marker pair resolver")
struct MarkerPairResolverTests {
    // MARK: - Constants

    private let thawBundleID = "com.stonerl.Thaw"
    private let ccBundleID = "com.apple.controlcenter"
    private let thawControlItemPrefix = "Thaw.ControlItem."

    // MARK: - Helpers

    private func icon(
        windowID: CGWindowID,
        title: String?,
        size: CGSize = CGSize(width: 116, height: 33)
    ) -> MarkerPairResolver.UnresolvedIcon {
        MarkerPairResolver.UnresolvedIcon(windowID: windowID, title: title, size: size)
    }

    private func marker(
        windowID: CGWindowID,
        title: String,
        size: CGSize = CGSize(width: 116, height: 33),
        owningPID: pid_t? = nil
    ) -> MarkerPairResolver.Marker {
        MarkerPairResolver.Marker(
            windowID: windowID,
            size: size,
            title: title,
            owningPID: owningPID
        )
    }

    /// Always-fails lookups, used by tests where neither path should
    /// resolve.
    private let neverResolve: (pid_t) -> String? = { _ in nil }
    private let neverResolveByBundle: (String) -> pid_t? = { _ in nil }

    // MARK: - Resolve

    /// The canonical observed shape: one unresolved icon with a
    /// generic "Item-0" title, one same-size marker with the agent
    /// bundle identifier as title, and the bundle-ID-to-PID lookup
    /// returning the agent's PID. The icon resolves via the title-
    /// lookup path because the marker's CG owner is Control Center
    /// (the macOS 26 reparenting case).
    @Test("An agent scene resolves through the title lookup")
    func agentSceneResolvesViaTitleLookup() {
        let icons = [icon(windowID: 11379, title: "Item-0")]
        let markers = [
            marker(
                windowID: 61456,
                title: "at.obdev.littlesnitch.agent",
                owningPID: 39187 // Control Center
            ),
        ]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 39187 {
                    return self.ccBundleID
                }
                if pid == 13496 {
                    return "at.obdev.littlesnitch.agent"
                }
                return nil
            },
            bundleIDToPID: { bundleID in
                bundleID == "at.obdev.littlesnitch.agent" ? 13496 : nil
            }
        )
        #expect(result.count == 1)
        #expect(result.first?.iconWindowID == 11379)
        #expect(result.first?.resolvedPID == 13496)
        #expect(result.first?.markerWindowID == 61456)
        #expect(result.first?.markerTitle == "at.obdev.littlesnitch.agent")
    }

    /// Marker's CG owner is the widget's real app (not CC, not Thaw):
    /// the owning-PID path resolves directly without falling through
    /// to the title lookup. The bundleIDToPID closure must NOT be
    /// invoked in this case.
    @Test("The owning-PID path is preferred over the title lookup")
    func owningPIDPathPreferredOverTitleLookup() {
        var bundleLookupCalled = false
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 555)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                pid == 555 ? "com.example.widget" : nil
            },
            bundleIDToPID: { _ in
                bundleLookupCalled = true
                return nil
            }
        )
        #expect(result.count == 1)
        #expect(result.first?.resolvedPID == 555)
        #expect(!bundleLookupCalled,
                "title-lookup path must not run when owning-PID path succeeds")
    }

    /// Marker's CG owner resolves to Control Center: the owning-PID
    /// path is rejected and the title lookup runs.
    @Test("A Control Center owner falls through to the title lookup")
    func ccOwnerFallsThroughToTitleLookup() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 200)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 200 {
                    return self.ccBundleID
                }
                if pid == 777 {
                    return "com.example.widget"
                }
                return nil
            },
            bundleIDToPID: { bundleID in
                bundleID == "com.example.widget" ? 777 : nil
            }
        )
        #expect(result.count == 1)
        #expect(result.first?.resolvedPID == 777)
    }

    /// Marker's CG owner resolves to Thaw itself: rejected, falls
    /// through to title lookup. The title-lookup result must also
    /// be checked for Thaw self-attribution (see the next test).
    @Test("A Thaw owner falls through to the title lookup")
    func thawOwnerFallsThroughToTitleLookup() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 100)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 100 {
                    return self.thawBundleID
                }
                if pid == 777 {
                    return "com.example.widget"
                }
                return nil
            },
            bundleIDToPID: { bundleID in
                bundleID == "com.example.widget" ? 777 : nil
            }
        )
        #expect(result.count == 1)
        #expect(result.first?.resolvedPID == 777)
    }

    /// Both paths resolve to Thaw: no resolution emitted. Defensive
    /// guarantee that Thaw's own PID is never attributed to a
    /// third-party widget regardless of where the lookup happens to
    /// land.
    @Test("Both paths resolving to Thaw produces no result")
    func bothPathsResolveToThawProducesNoResult() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: 100)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { _ in self.thawBundleID },
            bundleIDToPID: { _ in 100 }
        )
        #expect(result == [])
    }

    /// A marker titled with Control Center's own bundle identifier must not
    /// resolve an icon to Control Center. The owning-PID path already rejects
    /// it; the title-lookup path must too, or the icon gets a *resolved* CC
    /// PID, reads as a transient CC widget (canBeHidden false), and drops out
    /// of profile management — past every unresolved-sourcePID gate.
    @Test("A Control-Center-titled marker resolves nothing")
    func controlCenterTitledMarkerResolvesNothing() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.apple.controlcenter", owningPID: 1117)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { _ in self.ccBundleID },
            bundleIDToPID: { $0 == self.ccBundleID ? 1117 : nil }
        )
        #expect(result == [])
    }

    /// Two unresolved icons share the same size and there are two
    /// markers of that size: the ambiguity is unresolvable, so no
    /// pairings emit. Prevents the cross-attribution where an icon
    /// gets paired with the wrong marker.
    @Test("An ambiguous multi-match is skipped")
    func multiMatchSkipped() {
        let icons = [
            icon(windowID: 1, title: "Item-0"),
            icon(windowID: 2, title: "Item-0"),
        ]
        let markers = [
            marker(windowID: 10, title: "com.a.app", owningPID: 100),
            marker(windowID: 11, title: "com.b.app", owningPID: 200),
        ]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 100 {
                    return "com.a.app"
                }
                if pid == 200 {
                    return "com.b.app"
                }
                return nil
            },
            bundleIDToPID: { _ in nil }
        )
        #expect(result == [])
    }

    /// One marker cannot be claimed by several same-size icons: the
    /// first icon to claim the marker wins, the others are rejected.
    @Test("One marker cannot be claimed by several same-width icons")
    func oneMarkerCannotBeClaimedBySeveralIcons() {
        let size = CGSize(width: 38, height: 30)
        let icons = [
            icon(windowID: 34, title: "Sound", size: size),
            icon(windowID: 90, title: "WiFi", size: size),
            icon(windowID: 243, title: "Item-0", size: size),
        ]
        let markers = [marker(
            windowID: 3059,
            title: "com.sindresorhus.Pure-Paste",
            size: CGSize(width: 38, height: 33),
            owningPID: 1117 // Control Center
        )]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in pid == 1117 ? self.ccBundleID : "com.sindresorhus.Pure-Paste" },
            bundleIDToPID: { $0 == "com.sindresorhus.Pure-Paste" ? 1877 : nil }
        )
        #expect(result == [])
    }

    /// Icon whose own title is bundle-ID-shaped is not a candidate:
    /// it's a marker, not an icon. This prevents two markers from
    /// pairing with each other. The generic-titled icon resolves
    /// normally; the bundle-ID-titled "icon" is silently skipped.
    @Test("A bundle-ID-shaped icon title is skipped")
    func bundleIDShapedIconTitleIsSkipped() {
        // Two unrelated widgets at different sizes so neither
        // multi-matches; both have a generic-titled candidate icon
        // in the unresolved set, plus the bundle-ID-shaped "icon"
        // entry that the helper should skip.
        let icons = [
            icon(
                windowID: 1,
                title: "com.example.widget", // bundle-ID-shaped, should be skipped
                size: CGSize(width: 40, height: 33)
            ),
            icon(
                windowID: 2,
                title: "Item-0",
                size: CGSize(width: 116, height: 33)
            ),
        ]
        let markers = [
            // Same-size marker for windowID 1, but the icon itself
            // is filtered out by the bundle-ID-title check, so this
            // marker has nothing to pair with anyway.
            marker(
                windowID: 100,
                title: "com.example.widget",
                size: CGSize(width: 40, height: 33),
                owningPID: 100
            ),
            // Same-size marker for windowID 2.
            marker(
                windowID: 200,
                title: "com.another.widget",
                size: CGSize(width: 116, height: 33),
                owningPID: 200
            ),
        ]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { pid in
                if pid == 100 {
                    return "com.example.widget"
                }
                if pid == 200 {
                    return "com.another.widget"
                }
                return nil
            },
            bundleIDToPID: { bundleID in
                if bundleID == "com.example.widget" {
                    return 100
                }
                if bundleID == "com.another.widget" {
                    return 200
                }
                return nil
            }
        )
        #expect(result.count == 1)
        #expect(result.first?.iconWindowID == 2,
                "only the generic-titled icon should resolve; bundle-ID-titled icons are markers, not candidates")
    }

    /// Marker's windowID equals the icon's windowID (self-pair): the
    /// `windowID != icon.windowID` filter rejects self-pairings even
    /// though the size matches.
    @Test("A self-pairing is rejected")
    func selfPairingRejected() {
        // Same windowID for icon and marker — pathological input that
        // shouldn't occur, but the filter must hold.
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 1, title: "com.example.widget", owningPID: 100)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { _ in "com.example.widget" },
            bundleIDToPID: { _ in 100 }
        )
        #expect(result == [])
    }

    /// Size mismatch: no pairing. The marker's width differs from the
    /// icon's by 1 point, so they should not be considered the same
    /// widget.
    @Test("A size mismatch produces no result")
    func sizeMismatchProducesNoResult() {
        let icons = [icon(windowID: 1, title: "Item-0", size: CGSize(width: 116, height: 33))]
        let markers = [marker(
            windowID: 2,
            title: "com.example.widget",
            size: CGSize(width: 117, height: 33),
            owningPID: 100
        )]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: { _ in "com.example.widget" },
            bundleIDToPID: { _ in 100 }
        )
        #expect(result == [])
    }

    /// Neither owning-PID nor title-lookup resolves: no result. The
    /// algorithm bails cleanly when no resolution path succeeds.
    @Test("Neither path resolving produces no result")
    func neitherPathResolvesProducesNoResult() {
        let icons = [icon(windowID: 1, title: "Item-0")]
        let markers = [marker(windowID: 2, title: "com.example.widget", owningPID: nil)]
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: icons,
            markers: markers,
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: neverResolve,
            bundleIDToPID: neverResolveByBundle
        )
        #expect(result == [])
    }

    /// Empty inputs: empty output. Trivial guard.
    @Test("Empty inputs produce empty output")
    func emptyInputsProduceEmptyOutput() {
        let result = MarkerPairResolver.resolve(
            unresolvedIcons: [],
            markers: [],
            thawBundleID: thawBundleID,
            ccBundleID: ccBundleID,
            pidToBundleID: neverResolve,
            bundleIDToPID: neverResolveByBundle
        )
        #expect(result == [])
    }

    // MARK: - extractMarkers

    /// Non-dot titles are filtered out as non-markers.
    @Test("extractMarkers excludes generic titles")
    func extractMarkersExcludesGenericTitles() {
        let windows: [(windowID: CGWindowID, title: String?, size: CGSize, owningPID: pid_t?)] = [
            (1, "Item-0", CGSize(width: 116, height: 33), nil), // generic title
            (2, "", CGSize(width: 42, height: 33), nil), // empty
            (3, nil, CGSize(width: 22, height: 22), nil), // nil
            (4, "com.example.widget", CGSize(width: 116, height: 33), 100), // valid marker
        ]
        let markers = MarkerPairResolver.extractMarkers(
            from: windows,
            thawControlItemPrefix: thawControlItemPrefix,
            thawBundleID: thawBundleID
        )
        #expect(markers.map(\.windowID) == [4])
    }

    /// Thaw control items are excluded by the Thaw.ControlItem.
    /// prefix even though their titles contain dots.
    @Test("extractMarkers excludes Thaw control items")
    func extractMarkersExcludesThawControlItems() {
        let windows: [(windowID: CGWindowID, title: String?, size: CGSize, owningPID: pid_t?)] = [
            (1, "Thaw.ControlItem.Hidden", CGSize(width: 5016, height: 33), nil),
            (2, "Thaw.ControlItem.AlwaysHidden", CGSize(width: 5016, height: 33), nil),
            (3, "com.example.widget", CGSize(width: 24, height: 24), nil),
        ]
        let markers = MarkerPairResolver.extractMarkers(
            from: windows,
            thawControlItemPrefix: thawControlItemPrefix,
            thawBundleID: thawBundleID
        )
        #expect(markers.map(\.windowID) == [3])
    }

    /// The Thaw self-registration window (title equals the Thaw bundle
    /// identifier) is excluded so Thaw's own PID can never be
    /// attributed to a third-party widget via the title-lookup path.
    @Test("extractMarkers excludes the Thaw self-registration window")
    func extractMarkersExcludesThawSelfRegistration() {
        let windows: [(windowID: CGWindowID, title: String?, size: CGSize, owningPID: pid_t?)] = [
            (1, "com.stonerl.Thaw", CGSize(width: 33, height: 33), nil), // Thaw self
            (2, "com.example.widget", CGSize(width: 24, height: 24), nil),
        ]
        let markers = MarkerPairResolver.extractMarkers(
            from: windows,
            thawControlItemPrefix: thawControlItemPrefix,
            thawBundleID: thawBundleID
        )
        #expect(markers.map(\.windowID) == [2])
    }
}

/// Tests for HostedItemOwnership.titleIndicatesOwner, the corroboration
/// gate behind SourcePIDCache's loose spatial fallback. The accept/reject
/// cases are drawn directly from captured field logs so the dataset that
/// motivated the rule stays locked in: every accepted pair is a real
/// owner match seen unresolved, every rejected pair is a wrong neighbor or
/// same-vendor different-app collision seen in the same logs.
@Suite("Hosted item ownership")
struct HostedItemOwnershipTests {
    // MARK: - Accept: genuine owner matches observed unresolved in logs

    @Test("AirBuddy's menu matches the AirBuddy helper")
    func airBuddyMenuMatchesAirBuddyHelper() {
        // codes.rambo.AirBuddy.Menu hosted by Control Center, owned by the
        // helper whose bundle id extends the icon's distinctive component.
        #expect(
            HostedItemOwnership.titleIndicatesOwner(
                "codes.rambo.AirBuddy.Menu",
                bundleID: "codes.rambo.AirBuddyHelper"
            )
        )
    }

    @Test("SpamSieve matches case-insensitively")
    func spamSieveMatchesCaseInsensitively() {
        #expect(
            HostedItemOwnership.titleIndicatesOwner(
                "com.c-command.spamsieve",
                bundleID: "com.c-command.SpamSieve"
            )
        )
    }

    @Test("A Cotypist sub-item matches its parent bundle")
    func cotypistSubItemMatchesParentBundle() {
        #expect(
            HostedItemOwnership.titleIndicatesOwner(
                "app.cotypist.Cotypist.ModelRepository",
                bundleID: "app.cotypist.Cotypist"
            )
        )
    }

    // MARK: - Reject: same-vendor different-app collisions

    @Test("PixelSnap does not match CleanShot")
    func pixelSnapDoesNotMatchCleanShot() {
        // Both pl.maketheweb, but pixelsnap2 and cleanshotx are distinct
        // apps; a vendor-only prefix must never be enough.
        #expect(
            !HostedItemOwnership.titleIndicatesOwner(
                "pl.maketheweb.pixelsnap2",
                bundleID: "pl.maketheweb.cleanshotx"
            )
        )
        #expect(
            !HostedItemOwnership.titleIndicatesOwner(
                "pl.maketheweb.cleanshotx",
                bundleID: "pl.maketheweb.pixelsnap2"
            )
        )
    }

    @Test("A malformed vendor-only title never matches")
    func malformedVendorOnlyTitleNeverMatches() {
        // "pl.maketheweb." splits to ["pl", "maketheweb", ""], clearing the
        // three-component guard. Without the empty-component rejection the
        // trailing "" is a prefix of "cleanshotx" and the pair matches.
        #expect(!HostedItemOwnership.titleIndicatesOwner("pl.maketheweb.", bundleID: "pl.maketheweb.cleanshotx"))
    }

    // MARK: - Reject: unrelated neighbors that sat within the radius

    @Test("WireGuard does not match Updatest")
    func wireGuardDoesNotMatchUpdatest() {
        #expect(
            !HostedItemOwnership.titleIndicatesOwner(
                "com.wireguard.macos",
                bundleID: "app.updatest.Updatest"
            )
        )
    }

    @Test("SpamSieve does not match AusweisApp")
    func spamSieveDoesNotMatchAusweisApp() {
        // Same first component (com) but different vendor; one shared
        // component is not enough.
        #expect(
            !HostedItemOwnership.titleIndicatesOwner(
                "com.c-command.spamsieve",
                bundleID: "com.governikus.ausweisapp2"
            )
        )
    }

    // MARK: - Reject: non-reverse-DNS and empty titles

    @Test("A generic title never matches")
    func genericTitleNeverMatches() {
        #expect(!HostedItemOwnership.titleIndicatesOwner("Item-0", bundleID: "de.fauler-apfel.CMD-Z"))
    }

    @Test("A two-component title never matches")
    func twoComponentTitleNeverMatches() {
        #expect(!HostedItemOwnership.titleIndicatesOwner("mega.mac", bundleID: "mega.mac"))
    }

    @Test("A nil or empty title never matches")
    func nilAndEmptyTitleNeverMatch() {
        #expect(!HostedItemOwnership.titleIndicatesOwner(nil, bundleID: "codes.rambo.AirBuddyHelper"))
        #expect(!HostedItemOwnership.titleIndicatesOwner("", bundleID: "codes.rambo.AirBuddyHelper"))
    }

    @Test("A bare app-name title matches its bundle's last component")
    func bareAppNameMatchesLastComponent() {
        // windowID 3511 in the rc2 log: title "BetterTouchTool", AX child 15pt
        // // away in com.hegenberg.BetterTouchTool, refused for lack of shape.
        #expect(HostedItemOwnership.titleIndicatesOwner("BetterTouchTool", bundleID: "com.hegenberg.BetterTouchTool"))
    }

    @Test("A bare vendor component never matches")
    func bareVendorComponentNeverMatches() {
        #expect(!HostedItemOwnership.titleIndicatesOwner("hegenberg", bundleID: "com.hegenberg.BetterTouchTool"))
    }

    @Test("A bare title must equal the app component exactly")
    func bareTitleMustEqualAppComponentExactly() {
        // Substring agreement is not enough — "Clock" is a Control Center module.
        #expect(!HostedItemOwnership.titleIndicatesOwner("Clock", bundleID: "com.fabriceleyne.theclock"))
        #expect(!HostedItemOwnership.titleIndicatesOwner("Sound", bundleID: "com.rogueamoeba.soundsource"))
    }

    // MARK: - HostedItemOwnership.exactlyNamedOwner

    /// The #854 cluster: ten items whose title *is* their owner's bundle
    /// identifier, every one with a nil source PID. The hosted-extras pass
    /// finds the right app by title and then demands spatial confirmation
    /// against its AX children — which an item hosted by Control Center
    /// cannot supply, that being why it is unresolved. Exact equality needs
    /// no confirmation.
    @Test(
        "A title that is exactly a running bundle identifier names its owner",
        arguments: [
            "com.microsoft.OneDrive",
            "com.apple.TextInputMenuAgent",
            "us.zoom.xos",
            "theboringteam.boringnotch",
            "CalDigit.CalDigit-Docking-Station-Utility",
        ]
    )
    func exactTitleNamesOwner(bundleID: String) {
        #expect(
            HostedItemOwnership.exactlyNamedOwner(
                bundleID,
                runningBundleIDs: ["com.other.app", bundleID, "com.third.app"]
            ) == bundleID
        )
    }

    /// Case-insensitive, matching titleIndicatesOwner.
    @Test("Matching ignores case")
    func exactTitleIgnoresCase() {
        #expect(
            HostedItemOwnership.exactlyNamedOwner(
                "COM.MICROSOFT.ONEDRIVE",
                runningBundleIDs: ["com.microsoft.OneDrive"]
            ) == "com.microsoft.OneDrive"
        )
    }

    /// Near-misses are the relation's job, not this one's. Resolving
    /// without corroboration is only safe because the match is total.
    @Test(
        "A title that merely resembles an identifier does not qualify",
        arguments: ["com.microsoft.OneDrive-mac", "com.microsoft", "OneDrive", "com.microsoft.OneDrive.FinderSync"]
    )
    func nearMissesDoNotQualify(title: String) {
        #expect(
            HostedItemOwnership.exactlyNamedOwner(
                title,
                runningBundleIDs: ["com.microsoft.OneDrive"]
            ) == nil
        )
    }

    /// Generic and empty slot titles never resolve anything.
    @Test("Generic titles never qualify", arguments: ["Item-0", "", "Clock"])
    func genericTitlesNeverQualify(title: String) {
        #expect(
            HostedItemOwnership.exactlyNamedOwner(
                title,
                runningBundleIDs: ["com.microsoft.OneDrive", "Item-0"]
            ) == nil
        )
    }

    /// Two processes claiming one identifier is ambiguous; attributing the
    /// item to whichever was enumerated first is the misattribution every
    /// other pass avoids.
    @Test("An ambiguous identifier resolves to nothing")
    func ambiguousIdentifierDoesNotResolve() {
        #expect(
            HostedItemOwnership.exactlyNamedOwner(
                "com.microsoft.OneDrive",
                runningBundleIDs: ["com.microsoft.OneDrive", "com.microsoft.OneDrive"]
            ) == nil
        )
    }
}
