//
//  ControlCenterHostedMatchLogReplayTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
@testable import Thaw
import XCTest

/// Log-replay harness for the SourcePIDCache strict 1pt spatial pass, focused
/// on the macOS 26 Control-Center-hosted resolution case that this area keeps
/// regressing on.
///
/// macOS 26 hosts third-party status items under Control Center at the CG
/// layer. Two shapes look identical from the outside but must resolve in
/// opposite directions:
///
///   - Little Snitch publishes NO extras-bar child of its own, so the only AX
///     child on its icon is Control Center's. Binding it to Control Center
///     misattributes it and starves marker-pair / the provoke. It must stay
///     unresolved.
///   - The Clock publishes its OWN extras-bar child on the same icon, so it
///     must resolve to com.fabriceleyne.theclock.
///
/// A fix for either case has repeatedly broken the other. These tests parse the
/// real "diag unresolved" lines for both and drive the real
/// ControlCenterHostedMatch gate, so a future change that re-breaks one is
/// caught here. The named-module and Live-Activity gate guards keep the rest of
/// the Control Center family from collateral damage.
final class ControlCenterHostedMatchLogReplayTests: XCTestCase {
    private let cc = "com.apple.controlcenter"

    // MARK: - Parser characterization

    func testParserRecoversLittleSnitchScenario() throws {
        let scenario = try XCTUnwrap(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.littleSnitch)
        )
        XCTAssertEqual(scenario.windowID, 355)
        XCTAssertEqual(scenario.title, "Item-0")
        XCTAssertEqual(scenario.cgOwnerBundleID, cc)
        XCTAssertEqual(scenario.candidates.count, 3)
        XCTAssertEqual(
            scenario.candidates.first,
            .init(appBundleID: cc, distance: 0, enabled: nil),
            "the only child within 1pt is Control Center's own, at distance 0 with AXEnabled absent"
        )
    }

    func testParserRecoversTheClockScenario() throws {
        let scenario = try XCTUnwrap(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.theClock)
        )
        XCTAssertEqual(scenario.windowID, 6475)
        XCTAssertEqual(scenario.title, "Item-0")
        XCTAssertEqual(scenario.cgOwnerBundleID, cc)
        XCTAssertEqual(
            scenario.candidates.first,
            .init(appBundleID: "com.fabriceleyne.theclock", distance: 0, enabled: nil)
        )
        XCTAssertFalse(
            scenario.candidates.contains { $0.appBundleID == cc },
            "Control Center must not be a candidate for The Clock — its child is published by its own app"
        )
    }

    // MARK: - Regression locks: the mutually-protective pair

    /// RED before the gate, GREEN after. Little Snitch's icon must NOT bind to
    /// Control Center; it has to stay unresolved so it remains an orphan that
    /// reaches marker-pair resolution and the virtual-display provoke.
    func testLittleSnitchIconDoesNotBindToControlCenter() throws {
        let scenario = try XCTUnwrap(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.littleSnitch)
        )
        XCTAssertNil(
            ControlCenterHostedResolutionReplay.resolve(scenario),
            "windowID 355 must stay unresolved, not bind to com.apple.controlcenter"
        )
    }

    /// GREEN before and after the gate. The Clock must keep resolving to its
    /// own app: the gate refuses only Control Center's self-match, never a
    /// widget's own extras-bar child. This is the regression lock that protects
    /// The Clock from a future Little Snitch fix.
    func testTheClockResolvesToItsOwnApp() throws {
        let scenario = try XCTUnwrap(
            ControlCenterHostedResolutionReplay.parse(ControlCenterHostedResolutionLog.theClock)
        )
        XCTAssertEqual(
            ControlCenterHostedResolutionReplay.resolve(scenario),
            "com.fabriceleyne.theclock"
        )
    }

    // MARK: - Gate guards: the rest of the Control Center family

    /// Named Control Center modules carry descriptive titles, so the strict
    /// match identifies a real owner and is NOT a bare CC-hosted slot: they keep
    /// resolving to Control Center. System titles (TimeMachine) and nil/empty
    /// likewise never count as generic slots. Confirmed present as managed
    /// com.apple.controlcenter:<title> items in field logs.
    func testNamedControlCenterTitlesAreNotGenericSlots() {
        for title in [
            "WiFi", "Battery", "Bluetooth", "NowPlaying", "Clock", "BentoBox-0",
            "AudioVideoModule", "com.apple.menuextra.TimeMachine",
        ] {
            XCTAssertFalse(
                MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: title, ccBundleID: cc),
                "named Control Center module \(title) must keep resolving to Control Center"
            )
        }
        XCTAssertFalse(MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: nil, ccBundleID: cc))
        XCTAssertFalse(MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: "", ccBundleID: cc))
    }

    /// A generic Item-N icon matched by Control Center itself (Little Snitch, or
    /// a transient Live Activity) is a bare CC-hosted slot: it must be left
    /// unresolved so it stays an orphan for marker-pair / the provoke.
    func testGenericControlCenterHostedSlotDetected() {
        for title in ["Item-0", "Item-5", "Item-38"] {
            XCTAssertTrue(
                MarkerPairResolver.isCCHostedGenericSlot(appBundleID: cc, windowTitle: title, ccBundleID: cc),
                "generic Control-Center-hosted icon \(title) must not bind to Control Center"
            )
        }
    }

    /// The check only governs Control Center as the matcher: a generic Item-N
    /// title attributed to any other app (a widget's own extras child like The
    /// Clock, or Thaw's own items) — or to no known app at all — is never a bare
    /// CC slot.
    func testNonControlCenterMatcherIsNeverASlot() {
        for matcher in ["com.fabriceleyne.theclock", "com.stonerl.Thaw"] {
            XCTAssertFalse(
                MarkerPairResolver.isCCHostedGenericSlot(appBundleID: matcher, windowTitle: "Item-0", ccBundleID: cc),
                "\(matcher) matched its own child — must resolve to it, not be treated as a CC slot"
            )
        }
        XCTAssertFalse(
            MarkerPairResolver.isCCHostedGenericSlot(appBundleID: nil, windowTitle: "Item-0", ccBundleID: cc),
            "a nil matched bundle ID cannot be Control Center"
        )
    }

    /// The shared generic-title predicate, the single source of truth reused by
    /// both isCCHostedGenericSlot and MenuBarItemTag.isControlCenterGenericItem.
    func testGenericControlCenterTitlePredicate() {
        XCTAssertTrue(MarkerPairResolver.isGenericControlCenterTitle("Item-0"))
        XCTAssertTrue(MarkerPairResolver.isGenericControlCenterTitle("Item-1"))
        XCTAssertTrue(MarkerPairResolver.isGenericControlCenterTitle("Item-38"))
        XCTAssertFalse(MarkerPairResolver.isGenericControlCenterTitle("WiFi"))
        XCTAssertFalse(MarkerPairResolver.isGenericControlCenterTitle("BentoBox-0"))
        XCTAssertFalse(MarkerPairResolver.isGenericControlCenterTitle("com.apple.menuextra.TimeMachine"))
        // Regex boundary: "Item-" without a trailing index must not match.
        XCTAssertFalse(MarkerPairResolver.isGenericControlCenterTitle("Item-"))
        XCTAssertFalse(MarkerPairResolver.isGenericControlCenterTitle(nil))
        XCTAssertFalse(MarkerPairResolver.isGenericControlCenterTitle(""))
    }
}

/// Parses one SourcePIDCache "diag unresolved" line into a replayable window
/// scenario and drives the real strict-pass match decision. Test-only; models
/// just enough of the strict 1pt pass to characterize which app an icon would
/// bind to.
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
    /// Faithful reduction: within the 1pt tolerance the field logs show a
    /// single candidate (the next is always >= 40pt away), so "nearest
    /// qualifying candidate" equals the production pass's "first app whose child
    /// is within 1pt". The enabled != false guard mirrors the post-#667 matcher,
    /// where an absent AXEnabled attribute counts as enabled.
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
