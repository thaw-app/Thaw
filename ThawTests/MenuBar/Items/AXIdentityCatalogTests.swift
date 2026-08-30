//
//  AXIdentityCatalogTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

/// Covers the pure, non-AX helpers `AXIdentityCatalog` and
/// `MenuBarItemManager.ControlItemPair` use for frame correlation.
///
/// Walking a real `extrasMenuBar` requires the Accessibility permission
/// (TCC) and a live menu bar, so the identities a snapshot would actually
/// collect are not assertable in CI. What is assertable — and covered
/// below — is that `snapshot(hosts:)` degrades quietly when those reads
/// fail rather than trapping or hanging.
@Suite("AX identity catalog")
@MainActor
struct AXIdentityCatalogTests {
    // MARK: - AXIdentityCatalog.identity(for:in:)

    private func identity(frame: CGRect) -> AXIdentityCatalog.AXItemIdentity {
        AXIdentityCatalog.AXItemIdentity(identifier: nil, title: nil, help: nil, frame: frame)
    }

    @Test("Exact overlap wins")
    func identityReturnsExactOverlapWinner() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let exact = identity(frame: target)
        let distant = identity(frame: CGRect(x: 500, y: 500, width: 20, height: 20))

        let result = AXIdentityCatalog.identity(for: target, in: [distant, exact])

        #expect(result?.frame == target)
    }

    @Test("Overlap must exceed half of the smaller rectangle")
    func identityRequiresMoreThanHalfOfSmallerRectArea() {
        // Both rects have area 100 (so "smaller" area is 100). A 60-area
        // intersection (60%) clears the >50% threshold.
        let target = CGRect(x: 0, y: 0, width: 10, height: 10)
        let candidate = identity(frame: CGRect(x: 4, y: 0, width: 10, height: 10))

        let result = AXIdentityCatalog.identity(for: target, in: [candidate])

        #expect(result != nil)
    }

    @Test("Overlap at the threshold is rejected")
    func identityRejectsOverlapAtOrBelowHalfOfSmallerRectArea() {
        // Both rects have area 100 (so "smaller" area is 100). A 50-area
        // intersection is exactly the threshold, which the spec requires
        // to be exceeded, not merely met.
        let target = CGRect(x: 0, y: 0, width: 10, height: 10)
        let candidate = identity(frame: CGRect(x: 5, y: 0, width: 10, height: 10))

        let result = AXIdentityCatalog.identity(for: target, in: [candidate])

        #expect(result == nil)
    }

    @Test("A tie between top candidates is ambiguous")
    func identityReturnsNilOnTieBetweenTopCandidates() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        // Two distinct candidates, each fully containing target so both
        // clear the threshold with the exact same intersection area (the
        // full 400pt² of target) — an ambiguous tie.
        let exact = identity(frame: target)
        let taller = identity(frame: CGRect(x: 0, y: 0, width: 20, height: 30))

        let result = AXIdentityCatalog.identity(for: target, in: [exact, taller])

        #expect(result == nil)
    }

    @Test("Disjoint frames do not match")
    func identityReturnsNilForDisjointFrames() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let disjoint = identity(frame: CGRect(x: 1000, y: 1000, width: 20, height: 20))

        let result = AXIdentityCatalog.identity(for: target, in: [disjoint])

        #expect(result == nil)
    }

    @Test("An empty snapshot has no match")
    func identityReturnsNilForEmptySnapshot() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)

        let result = AXIdentityCatalog.identity(for: target, in: [])

        #expect(result == nil)
    }

    @Test("The highest qualifying overlap wins")
    func identityTakesHighestOverlapAmongMultipleCandidates() {
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let partial = identity(frame: CGRect(x: 15, y: 0, width: 20, height: 20)) // small overlap, below threshold
        let full = identity(frame: target) // full overlap

        let result = AXIdentityCatalog.identity(for: target, in: [partial, full])

        #expect(result?.frame == target)
    }

    @Test("A later strictly better candidate replaces the current best")
    func identityReplacesAnEarlierBestWithAStrictlyBetterOne() {
        // Both candidates clear the threshold, so the first becomes the
        // standing best and the second has to displace it. The
        // above-threshold-then-better ordering is what distinguishes this
        // from testIdentityTakesHighestOverlapAmongMultipleCandidates,
        // where the weaker candidate never qualifies at all.
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let good = identity(frame: CGRect(x: 6, y: 0, width: 20, height: 20)) // 280pt², 70%
        let better = identity(frame: target) // 400pt², 100%

        let result = AXIdentityCatalog.identity(for: target, in: [good, better])

        #expect(result?.frame == target)
    }

    @Test("A later weaker candidate does not replace the best")
    func identityIgnoresAWeakerCandidateArrivingAfterTheBest() {
        // The same pair in the opposite order: the standing best must
        // survive a later, qualifying-but-worse candidate.
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let better = identity(frame: target)
        let good = identity(frame: CGRect(x: 6, y: 0, width: 20, height: 20))

        let result = AXIdentityCatalog.identity(for: target, in: [better, good])

        #expect(result?.frame == target)
    }

    @Test("A better candidate resolves an earlier tie")
    func identityRecoversFromAnEarlierTieWhenABetterCandidateArrives() {
        // A tie only makes the result ambiguous while it is still the best
        // score. Something strictly better resolves the ambiguity, so the
        // tie flag has to be cleared rather than latched.
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let tiedA = identity(frame: CGRect(x: 6, y: 0, width: 20, height: 20)) // 280pt²
        let tiedB = identity(frame: CGRect(x: -6, y: 0, width: 20, height: 20)) // 280pt²
        let winner = identity(frame: target) // 400pt²

        let result = AXIdentityCatalog.identity(for: target, in: [tiedA, tiedB, winner])

        #expect(result?.frame == target)
    }

    @Test("Zero-area candidates do not match")
    func identityIgnoresZeroAreaCandidates() {
        // A zero-area frame can never cover more than half of itself, and
        // dividing by its area would be undefined.
        let target = CGRect(x: 0, y: 0, width: 20, height: 20)
        let degenerate = identity(frame: CGRect(x: 5, y: 5, width: 0, height: 0))

        #expect(AXIdentityCatalog.identity(for: target, in: [degenerate]) == nil)
    }

    // MARK: - AXIdentityCatalog.snapshot(hosts:)

    @Test("A snapshot with no hosts is empty")
    func snapshotOfNoHostsIsEmpty() {
        // The host list is empty whenever none of the known menu bar hosts
        // are running, which must be a quiet no-op rather than an error.
        #expect(AXIdentityCatalog.snapshot(hosts: []).isEmpty)
    }

    @Test("An unavailable Accessibility tree degrades quietly")
    func snapshotWithoutAccessibilityPermissionDegradesQuietly() {
        // Without the Accessibility permission (the CI case) every AX read
        // fails, so the walk finds no extras menu bar to descend into. The
        // contract under test is that this degrades to a well-formed
        // snapshot instead of trapping or hanging on the messaging timeout.
        let snapshot = AXIdentityCatalog.snapshot(hosts: [.current])

        #expect(snapshot.allSatisfy { !$0.frame.isNull })
    }

    // MARK: - MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates:axFrames:)

    private typealias CandidateFrame = MenuBarItemManager.ControlItemPair.CandidateFrame

    @Test("AX-frame control pairs cannot reposition dividers")
    func axFrameControlPairCannotRepositionDividers() {
        let hidden = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 100,
            bounds: CGRect(x: 100, y: 0, width: 20, height: 20)
        )
        let pair = MenuBarItemManager.ControlItemPair(
            hidden: hidden,
            alwaysHidden: nil,
            resolution: .axFrameCorrelation
        )

        #expect(!pair.canRepositionControlItems)
    }

    @Test("Identity-resolved control pairs can reposition dividers")
    func identityControlPairCanRepositionDividers() {
        let hidden = MenuBarItem.fixture(
            tag: .hiddenControlItem,
            windowID: 100,
            bounds: CGRect(x: 100, y: 0, width: 20, height: 20)
        )
        let pair = MenuBarItemManager.ControlItemPair(hidden: hidden, alwaysHidden: nil)

        #expect(pair.canRepositionControlItems)
    }

    @Test("AX frames select hidden control items among distractors")
    func selectViaAXFrameMatchesHiddenAndAlwaysHiddenAmongDistractors() {
        let hiddenFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let alwaysHiddenFrame = CGRect(x: 200, y: 0, width: 20, height: 20)

        let candidates = [
            CandidateFrame(index: 0, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), isOwnProcess: false), // distractor, third-party
            CandidateFrame(index: 1, bounds: hiddenFrame, isOwnProcess: true),
            CandidateFrame(index: 2, bounds: CGRect(x: 300, y: 0, width: 20, height: 20), isOwnProcess: false), // distractor
            CandidateFrame(index: 3, bounds: alwaysHiddenFrame, isOwnProcess: true),
        ]
        let axFrames = [hiddenFrame, alwaysHiddenFrame]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: axFrames)

        #expect(result == [1, 3])
    }

    @Test("AX frame selection tolerates small offsets")
    func selectViaAXFrameToleratesSmallFrameOffsets() {
        // AX-reported frame is a few points off from the CG window bounds.
        let hiddenFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let axHiddenFrame = CGRect(x: 102, y: 1, width: 20, height: 20)

        let candidates = [
            CandidateFrame(index: 0, bounds: hiddenFrame, isOwnProcess: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: [axHiddenFrame])

        #expect(result == [0])
    }

    @Test("AX frame selection ignores third-party candidates")
    func selectViaAXFrameIgnoresThirdPartyCandidatesEvenOnFrameMatch() {
        let frame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let candidates = [
            CandidateFrame(index: 0, bounds: frame, isOwnProcess: false),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: [frame])

        #expect(result == nil)
    }

    @Test("AX frame selection refuses duplicate current-process candidates")
    func selectViaAXFrameRejectsAmbiguousDuplicateDividers() {
        let frame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let candidates = [
            CandidateFrame(index: 0, bounds: frame, isOwnProcess: true),
            CandidateFrame(index: 1, bounds: frame, isOwnProcess: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(
            candidates: candidates,
            axFrames: [frame]
        )

        #expect(result == nil)
    }

    // MARK: - MenuBarItemManager.previousPIDIsLive

    /// The reconciliation guard prefers a cached PID over a fresh
    /// resolution, because AX spatial matching can mis-match. That only
    /// holds while the cached process exists: once it has exited — an
    /// item's owner relaunching, or Control Center respawning and
    /// recreating every status item, both in the #854 logs — reverting
    /// pins the item to a dead process.
    @Test("This process is live")
    func currentProcessIsLive() {
        #expect(MenuBarItemManager.previousPIDIsLive(ProcessInfo.processInfo.processIdentifier))
    }

    /// launchd always exists and is never ours to signal, so it exercises
    /// the EPERM branch: exists, but not signalable, which still counts.
    @Test("A process we may not signal still counts as live")
    func unsignalableProcessIsLive() {
        #expect(MenuBarItemManager.previousPIDIsLive(1))
    }

    /// A PID that cannot be allocated is the unambiguous dead answer.
    @Test("An impossible PID is not live")
    func impossiblePIDIsNotLive() {
        #expect(!MenuBarItemManager.previousPIDIsLive(Int32.max))
    }

    // MARK: - MenuBarItemManager.eventTargetPID

    /// Historic behaviour: aim at the app whose status item it is.
    ///
    /// Correct before macOS 26, when that app also owned the window. On 26
    /// Control Center hosts every status item window, so this targets a
    /// process that does not own the window being dragged.
    @Test("By default a resolved source PID wins")
    func eventTargetPrefersSourcePIDByDefault() {
        #expect(
            MenuBarItemManager.eventTargetPID(sourcePID: 1388, ownerPID: 492, preferWindowOwner: false) == 1388
        )
    }

    /// The existing fallback: with no owning app known, the window's owner
    /// is all there is — which is the host, and the target the flag makes
    /// unconditional.
    @Test("An unresolved source PID already falls back to the window owner")
    func eventTargetFallsBackToOwner() {
        #expect(
            MenuBarItemManager.eventTargetPID(sourcePID: nil, ownerPID: 492, preferWindowOwner: false) == 492
        )
    }

    /// The flag under test: always address the process that owns the window
    /// being dragged, which on macOS 26 is the host rather than the app
    /// whose status item it is.
    @Test("Preferring the window owner overrides a resolved source PID")
    func eventTargetPrefersWindowOwnerWhenFlagged() {
        #expect(
            MenuBarItemManager.eventTargetPID(sourcePID: 1388, ownerPID: 492, preferWindowOwner: true) == 492
        )
    }

    /// With the flag on, an unresolved owner changes nothing — which is the
    /// point: the move stops depending on identity.
    @Test("The window owner is used whether or not the source PID resolved")
    func eventTargetIgnoresSourcePIDWhenFlagged() {
        #expect(
            MenuBarItemManager.eventTargetPID(sourcePID: nil, ownerPID: 492, preferWindowOwner: true) == 492
        )
    }

    // MARK: - MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem

    /// Thaw created its control items and holds their windows, so when one
    /// goes missing from the enumerated list it can be rebuilt from its own
    /// window instead of guessed at. The gate is deliberately narrow: an
    /// authoritative ID in hand, and that window absent from the list.
    @Test("A known control window missing from the list is recovered")
    func recoversAuthoritativeWindowAbsentFromList() {
        #expect(
            MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem(
                authoritativeWindowID: 120,
                itemWindowIDs: [118, 122, 200]
            )
        )
    }

    /// Present in the list means the primary lookup already claimed it;
    /// rebuilding would duplicate an item the caller expects to have been
    /// removed from `items`.
    @Test("A control window present in the list is left to the primary lookup")
    func doesNotRecoverWindowPresentInList() {
        #expect(
            !MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem(
                authoritativeWindowID: 120,
                itemWindowIDs: [118, 120, 122]
            )
        )
    }

    /// Without an authoritative ID there is nothing to be authoritative
    /// about — at startup the status item may not exist yet, and the tag and
    /// title fallbacks are the right answer.
    @Test("No authoritative window ID means no recovery")
    func doesNotRecoverWithoutAuthoritativeID() {
        #expect(
            !MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem(
                authoritativeWindowID: nil,
                itemWindowIDs: [118, 120]
            )
        )
    }

    /// An empty list is the degenerate form of the case this exists for:
    /// enumeration returned nothing, and the fallbacks have nothing to work
    /// with either.
    @Test("An empty item list still recovers a known window")
    func recoversFromEmptyList() {
        #expect(
            MenuBarItemManager.ControlItemPair.shouldRecoverOwnControlItem(
                authoritativeWindowID: 120,
                itemWindowIDs: []
            )
        )
    }

    /// Regression for #923 / #924 / #927.
    ///
    /// The visible control item is own-process, so it qualifies on frame
    /// alone. When the hidden divider is missing from the candidate list —
    /// parked far offscreen, or dropped by the active-space filter — it can
    /// be the only own-process candidate left, and the hidden AX frame
    /// correlates onto it. Returned as the hidden divider, every section
    /// boundary downstream is then measured from the wrong window: the
    /// hidden section reads as zero width, and both the save and the apply
    /// refuse (the latter since c3317dfd), so the layout stops persisting
    /// and every item lands visible after a restart.
    ///
    /// Refusing to match is the correct outcome. The caller logs "missing
    /// control items" and bails, which is recoverable; returning the wrong
    /// window is not.
    @Test("AX frame selection never returns the visible control item")
    func selectViaAXFrameRejectsVisibleControlItem() {
        let frame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let candidates = [
            CandidateFrame(index: 0, bounds: frame, isOwnProcess: true, isVisibleControlItem: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: [frame])

        #expect(result == nil)
    }

    /// The exclusion must not cost a legitimate match: with the hidden
    /// divider present, it still wins even though the visible control item
    /// is sitting in the list too.
    @Test("The visible control item is skipped in favour of the real divider")
    func selectViaAXFrameSkipsVisibleAndMatchesHidden() {
        let visibleFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let hiddenFrame = CGRect(x: 200, y: 0, width: 20, height: 20)

        let candidates = [
            CandidateFrame(index: 0, bounds: visibleFrame, isOwnProcess: true, isVisibleControlItem: true),
            CandidateFrame(index: 1, bounds: hiddenFrame, isOwnProcess: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(
            candidates: candidates,
            axFrames: [hiddenFrame]
        )

        #expect(result == [1])
    }

    /// The visible item must not be able to absorb the always-hidden slot
    /// either — the pair is selected by the same loop.
    @Test("The visible control item cannot take the always-hidden slot")
    func selectViaAXFrameRejectsVisibleForAlwaysHidden() {
        let hiddenFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let visibleFrame = CGRect(x: 200, y: 0, width: 20, height: 20)

        let candidates = [
            CandidateFrame(index: 0, bounds: hiddenFrame, isOwnProcess: true),
            CandidateFrame(index: 1, bounds: visibleFrame, isOwnProcess: true, isVisibleControlItem: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(
            candidates: candidates,
            axFrames: [hiddenFrame, visibleFrame]
        )

        #expect(result == [0])
    }

    @Test("AX frame selection returns the only matching control item")
    func selectViaAXFrameReturnsOnlyHiddenWhenNoSecondMatch() {
        let hiddenFrame = CGRect(x: 100, y: 0, width: 20, height: 20)
        let candidates = [
            CandidateFrame(index: 0, bounds: hiddenFrame, isOwnProcess: true),
            CandidateFrame(index: 1, bounds: CGRect(x: 999, y: 999, width: 20, height: 20), isOwnProcess: true),
        ]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: [hiddenFrame])

        #expect(result == [0])
    }

    @Test("AX frame selection returns nil without a correlation")
    func selectViaAXFrameReturnsNilWhenNoCandidateCorrelates() {
        let candidates = [
            CandidateFrame(index: 0, bounds: CGRect(x: 0, y: 0, width: 20, height: 20), isOwnProcess: true),
        ]
        let axFrames = [CGRect(x: 500, y: 500, width: 20, height: 20)]

        let result = MenuBarItemManager.ControlItemPair.selectViaAXFrame(candidates: candidates, axFrames: axFrames)

        #expect(result == nil)
    }

    @Suite("Tree traversal")
    @MainActor
    struct Traversal {
        private struct Node {
            let id: Int
            let frame: CGRect?
            let children: [Node]
        }

        @Test("The walk collects framed nodes through the maximum depth")
        func walkHonorsDepthAndSkipsFramelessNodes() {
            let root = chain(depth: 7, framelessDepth: 2)
            var visited = 0
            var identities = [AXIdentityCatalog.AXItemIdentity]()

            walk(root, visited: &visited, identities: &identities)

            #expect(visited == 7)
            #expect(identities.compactMap(\.identifier) == ["0", "1", "3", "4", "5", "6"])
        }

        @Test("A walk starting beyond the maximum depth is ignored")
        func walkRejectsExcessiveStartingDepth() {
            let root = Node(id: 0, frame: unitFrame(at: 0), children: [])
            var visited = 0
            var identities = [AXIdentityCatalog.AXItemIdentity]()

            walk(root, depth: 7, visited: &visited, identities: &identities)

            #expect(visited == 0)
            #expect(identities.isEmpty)
        }

        @Test("The walk stops at the global element cap")
        func walkHonorsElementCap() {
            let children = (1 ... 600).map { id in
                Node(id: id, frame: unitFrame(at: id), children: [])
            }
            let root = Node(id: 0, frame: unitFrame(at: 0), children: children)
            var visited = 0
            var identities = [AXIdentityCatalog.AXItemIdentity]()

            walk(root, visited: &visited, identities: &identities)

            #expect(visited == 512)
            #expect(identities.count == 512)
            #expect(identities.last?.identifier == "511")
        }

        @Test("An expired deadline prevents any traversal")
        func walkHonorsDeadline() {
            let root = Node(id: 0, frame: unitFrame(at: 0), children: [])
            var visited = 0
            var identities = [AXIdentityCatalog.AXItemIdentity]()

            walk(
                root,
                visited: &visited,
                identities: &identities,
                deadline: ContinuousClock.now.advanced(by: .milliseconds(-1))
            )

            #expect(visited == 0)
            #expect(identities.isEmpty)
        }

        private func walk(
            _ root: Node,
            depth: Int = 0,
            visited: inout Int,
            identities: inout [AXIdentityCatalog.AXItemIdentity],
            deadline: ContinuousClock.Instant = ContinuousClock.now.advanced(by: .seconds(1))
        ) {
            AXIdentityCatalog.walk(
                root,
                depth: depth,
                visited: &visited,
                deadline: deadline,
                into: &identities,
                identityFor: { node in
                    node.frame.map { frame in
                        AXIdentityCatalog.AXItemIdentity(
                            identifier: String(node.id),
                            title: nil,
                            help: nil,
                            frame: frame
                        )
                    }
                },
                childrenFor: \Node.children
            )
        }

        private func chain(depth: Int, framelessDepth: Int?) -> Node {
            var node = Node(
                id: depth,
                frame: depth == framelessDepth ? nil : unitFrame(at: depth),
                children: []
            )
            guard depth > 0 else { return node }

            for id in stride(from: depth - 1, through: 0, by: -1) {
                node = Node(
                    id: id,
                    frame: id == framelessDepth ? nil : unitFrame(at: id),
                    children: [node]
                )
            }
            return node
        }

        private func unitFrame(at offset: Int) -> CGRect {
            CGRect(x: offset, y: 0, width: 1, height: 1)
        }
    }
}
