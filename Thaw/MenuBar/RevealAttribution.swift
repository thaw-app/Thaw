//
//  RevealAttribution.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import MenuBarModel

/// Who opened the section that is revealed now: the user, or Thaw by itself.
///
/// Always-show and the zen restore reveal sections with nobody at the bar. They run their
/// reveals through ``policy(_:)``, and the repairs those reveals ask for carry
/// ``RepairOrchestrator/Cause/policyReveal``, which neither calls off the automatic passes
/// that are planned nor refills the loop budget.
///
/// The kit pins the order inside `show`, before it changes the revealed section, so
/// ``preRevealCause`` answers for the call in progress. It asks for the settled restore about
/// a second after `show` returns, so ``reconcileCause`` answers for the reveal on screen. That
/// reveal stays Thaw's until the revealed section goes back to nil, or until a reveal made
/// outside ``policy(_:)`` replaces it.
@MainActor
final class RevealAttribution {
    /// Something the attribution is told: a policy call starting or ending, or the revealed section changing.
    nonisolated enum Event: Equatable {
        case policyBegan
        case policyEnded
        case revealedSectionChanged(MenuBarSectionName?)
    }

    /// What the attribution has seen, kept apart from the publisher so it can be driven one event at a time.
    nonisolated struct State: Equatable {
        /// How many policy calls are running. A reveal made inside one is Thaw's own.
        private(set) var policyCalls = 0
        /// Whether the section revealed now was revealed inside a policy call.
        private(set) var revealIsPolicy = false
        /// The section revealed now, so the same value published again changes nothing.
        private(set) var revealed: MenuBarSectionName?

        var isInPolicyCall: Bool {
            policyCalls > 0
        }

        mutating func apply(_ event: Event) {
            switch event {
            case .policyBegan:
                policyCalls += 1
            case .policyEnded:
                policyCalls = max(policyCalls - 1, 0)
            case let .revealedSectionChanged(section):
                guard section != revealed else { return }
                revealed = section
                // A hide ends the mark, and any other change belongs to whoever made it.
                revealIsPolicy = section != nil && isInPolicyCall
            }
        }
    }

    private(set) var state = State()
    private var subscription: AnyCancellable?

    /// Runs a reveal or hide Thaw makes by itself, marking the reveal it causes as policy.
    func policy(_ reveal: () -> Void) {
        state.apply(.policyBegan)
        defer { state.apply(.policyEnded) }
        reveal()
    }

    /// The cause for the order pinned just before a section is revealed.
    var preRevealCause: RepairOrchestrator.Cause {
        state.isInPolicyCall ? .policyReveal : .revealStarting
    }

    /// The cause for the restores a revealed section asks for once the bar settles.
    var reconcileCause: RepairOrchestrator.Cause {
        state.revealIsPolicy ? .policyReveal : .sectionRevealed
    }

    func noteRevealedSection(_ section: MenuBarSectionName?) {
        state.apply(.revealedSectionChanged(section))
    }

    /// Follows the revealed section. The publisher has to deliver each change as it is made, on the
    /// main actor, so a change made inside a policy call is seen while that call is still running.
    func observe(_ revealedSection: AnyPublisher<MenuBarSectionName?, Never>) {
        subscription = revealedSection.sink { [weak self] in self?.noteRevealedSection($0) }
    }
}
