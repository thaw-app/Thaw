//
//  ControlCenterHostedMatchLogReplayTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import Testing
@testable import Thaw

/// Log-replay harness for the SourcePIDCache strict 1pt spatial pass.
///
/// macOS 26 hosts third-party status items under Control Center at the CG
/// layer. Two identical-looking shapes must resolve in opposite directions:
///
///   - Little Snitch publishes no extras-bar child, so the only AX child on
///     its icon is Control Center's. It must stay unresolved for marker-pair.
///   - The Clock publishes its own extras-bar child on the same icon, so it
///     must resolve to com.fabriceleyne.theclock.
///
/// A fix for either case has repeatedly broken the other. These tests replay
/// the real "diag unresolved" lines for both through the real gate.
@Suite("Control Center hosted match log replay")
struct ControlCenterHostedMatchLogReplayTests {
    private let cc = "com.apple.controlcenter"

    // MARK: - Parser characterization

    @Test("The parser recovers the Little Snitch scenario")
    func parserRecoversLittleSnitchScenario() throws {
        let scenario = try #require(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.littleSnitch)
        )
        #expect(scenario.windowID == 355)
        #expect(scenario.title == "Item-0")
        #expect(scenario.cgOwnerBundleID == cc)
        #expect(scenario.candidates.count == 3)
        #expect(
            scenario.candidates.first == ControlCenterHostedResolutionReplay.CandidateChild(
                appBundleID: cc,
                distance: 0,
                enabled: nil
            ),
            "the only child within 1pt is Control Center's own, at distance 0 with AXEnabled absent"
        )
    }

    @Test("The parser recovers The Clock scenario")
    func parserRecoversTheClockScenario() throws {
        let scenario = try #require(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.theClock)
        )
        #expect(scenario.windowID == 6475)
        #expect(scenario.title == "Item-0")
        #expect(scenario.cgOwnerBundleID == cc)
        #expect(
            scenario.candidates.first == ControlCenterHostedResolutionReplay.CandidateChild(
                appBundleID: "com.fabriceleyne.theclock",
                distance: 0,
                enabled: nil
            )
        )
        #expect(
            !scenario.candidates.contains { $0.appBundleID == cc },
            "Control Center must not be a candidate for The Clock — its child is published by its own app"
        )
    }

    // MARK: - Regression locks: the mutually-protective pair

    /// Little Snitch's icon must stay unresolved so it reaches marker-pair
    /// resolution.
    @Test("The Little Snitch icon does not bind to Control Center")
    func littleSnitchIconDoesNotBindToControlCenter() throws {
        let scenario = try #require(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.littleSnitch)
        )
        #expect(
            ControlCenterHostedResolutionReplay.resolve(scenario) == nil,
            "windowID 355 must stay unresolved, not bind to com.apple.controlcenter"
        )
    }

    /// The gate refuses only Control Center's self-match, never a widget's own
    /// extras-bar child.
    @Test("The Clock resolves to its own app")
    func theClockResolvesToItsOwnApp() throws {
        let scenario = try #require(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.theClock)
        )
        #expect(
            ControlCenterHostedResolutionReplay.resolve(scenario) == "com.fabriceleyne.theclock"
        )
    }

    // MARK: - Gate guards: the rest of the Control Center family

    /// Named modules, system titles (TimeMachine), and nil/empty titles are
    /// not generic slots, so they keep resolving to Control Center.
    @Test("Named Control Center titles are not generic slots")
    func namedControlCenterTitlesAreNotGenericSlots() {
        for title in [
            "WiFi", "Battery", "Bluetooth", "NowPlaying", "Clock", "BentoBox-0",
            "AudioVideoModule", "com.apple.menuextra.TimeMachine",
        ] {
            #expect(
                !MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: title, ccBundleID: cc),
                "named Control Center module \(title) must keep resolving to Control Center"
            )
        }
        #expect(!MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: nil, ccBundleID: cc))
        #expect(!MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: "", ccBundleID: cc))
    }

    /// A generic Item-N icon matched by Control Center itself (Little Snitch, or
    /// a transient Live Activity) is a bare CC-hosted slot: it must be left
    /// unresolved so it stays an orphan for marker-pair resolution.
    @Test("A generic Control-Center-hosted slot is detected")
    func genericControlCenterHostedSlotDetected() {
        for title in ["Item-0", "Item-5", "Item-38"] {
            #expect(
                MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: title, ccBundleID: cc),
                "generic Control-Center-hosted icon \(title) must not bind to Control Center"
            )
        }
    }

    /// The check only governs Control Center as the matcher. A generic Item-N
    /// title attributed to any other app, or to none, is never a bare CC slot.
    @Test("A non-Control-Center matcher is never a slot")
    func nonControlCenterMatcherIsNeverASlot() {
        for matcher in ["com.fabriceleyne.theclock", "com.stonerl.Thaw"] {
            #expect(
                !MarkerPairResolver.isCCHostedGenericSlot(
                    appBundleID: matcher,
                    windowTitle: "Item-0",
                    ccBundleID: cc
                ),
                "\(matcher) matched its own child — must resolve to it, not be treated as a CC slot"
            )
        }
        #expect(
            !MarkerPairResolver.isCCHostedGenericSlot(appBundleID: nil, windowTitle: "Item-0", ccBundleID: cc),
            "a nil matched bundle ID cannot be Control Center"
        )
    }

    /// Shared by isCCHostedGenericSlot and MenuBarItemTag.isControlCenterGenericItem.
    @Test("The generic Control Center title predicate matches only Item-N titles")
    func genericControlCenterTitlePredicate() {
        #expect(MarkerPairResolver.isGenericControlCenterTitle("Item-0"))
        #expect(MarkerPairResolver.isGenericControlCenterTitle("Item-1"))
        #expect(MarkerPairResolver.isGenericControlCenterTitle("Item-38"))
        #expect(!MarkerPairResolver.isGenericControlCenterTitle("WiFi"))
        #expect(!MarkerPairResolver.isGenericControlCenterTitle("BentoBox-0"))
        #expect(!MarkerPairResolver.isGenericControlCenterTitle("com.apple.menuextra.TimeMachine"))
        // Regex boundary: "Item-" without a trailing index must not match.
        #expect(!MarkerPairResolver.isGenericControlCenterTitle("Item-"))
        #expect(!MarkerPairResolver.isGenericControlCenterTitle(nil))
        #expect(!MarkerPairResolver.isGenericControlCenterTitle(""))
    }
}

/// Parses a SourcePIDCache "diag unresolved" line and replays the strict 1pt
/// pass to show which app an icon would bind to.
enum ControlCenterHostedResolutionReplay {
    /// One nearest-candidate AX child from the diag line's `nearest=[...]` list.
    struct CandidateChild: Equatable {
        let appBundleID: String
        let distance: CGFloat
        /// nil = AXEnabled attribute absent (treated as enabled post-#667);
        /// true/false = explicit value.
        let enabled: Bool?
    }

    /// One unresolved menu bar window reconstructed from a diag line.
    struct WindowScenario: Equatable {
        let windowID: CGWindowID
        let title: String?
        let cgOwnerBundleID: String?
        let candidates: [CandidateChild]
    }

    static func parse(_ text: String) -> WindowScenario? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let widMatch = line.firstMatch(of: /windowID=(\d+)/),
              let windowID = CGWindowID(widMatch.output.1)
        else {
            return nil
        }
        let title = line.firstMatch(of: /title=(\S+)/).map { String($0.output.1) }
        let cgOwner = line.firstMatch(of: /cgOwner=([A-Za-z0-9._-]+):pid=/).map { String($0.output.1) }

        var candidates = [CandidateChild]()
        if let nearest = line.firstMatch(of: /nearest=\[(.*)\]/) {
            for match in String(nearest.output.1)
                .matches(of: /([A-Za-z0-9._-]+)@([0-9.]+)\(enabled=(nil|true|false)\)/)
            {
                let enabled: Bool? = match.output.3 == "nil" ? nil : (match.output.3 == "true")
                candidates.append(CandidateChild(
                    appBundleID: String(match.output.1),
                    distance: Double(match.output.2).map { CGFloat($0) } ?? .greatestFiniteMagnitude,
                    enabled: enabled
                ))
            }
        }

        return WindowScenario(windowID: windowID, title: title, cgOwnerBundleID: cgOwner, candidates: candidates)
    }

    /// Replays the strict 1pt spatial pass for one window through the real
    /// MarkerPairResolver.isCCHostedGenericSlot check, returning the bundle ID
    /// the icon would resolve to, or nil if it stays unresolved.
    ///
    /// Field logs show one candidate within 1pt (the next is >= 40pt away), so
    /// nearest equals the production pass's first match. An absent AXEnabled
    /// counts as enabled, as in the post-#667 matcher.
    static func resolve(_ scenario: WindowScenario, ccBundleID: String = "com.apple.controlcenter") -> String? {
        for candidate in scenario.candidates.sorted(by: { $0.distance < $1.distance }) {
            guard candidate.distance <= 1 else { break }
            guard candidate.enabled != false else { continue }
            // A bare CC-hosted generic slot identifies no owner; leave it
            // unresolved so marker-pair can supply the real owner PID.
            if MarkerPairResolver.isCCHostedGenericSlot(
                appBundleID: candidate.appBundleID,
                windowTitle: scenario.title,
                ccBundleID: ccBundleID
            ) {
                continue
            }
            return candidate.appBundleID
        }
        return nil
    }
}
