//
//  AlwaysShowHiddenItemsController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel
import Observation

@MainActor
final class AlwaysShowHiddenItemsController {
    private let activeDisplayID: () -> CGDirectDisplayID?
    private let alwaysShow: (CGDirectDisplayID) -> Bool
    private let usesThawBar: (CGDirectDisplayID) -> Bool
    private let isZenModeActive: () -> Bool
    private let revealedSection: () -> MenuBarSectionName?
    private let reveal: (MenuBarSectionName?) -> Void
    private let resetPresentation: () -> Void
    private var isAlwaysShowRevealActive = false
    private var observationTask: Task<Void, Never>?
    private var displayChangeHold = AlwaysShowDisplayChangeHold()
    private var displayChangeSubscriptions = Set<AnyCancellable>()

    init(
        activeDisplayID: @escaping () -> CGDirectDisplayID? = {
            (NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.displayID
        },
        alwaysShow: @escaping (CGDirectDisplayID) -> Bool,
        usesThawBar: @escaping (CGDirectDisplayID) -> Bool,
        isZenModeActive: @escaping () -> Bool,
        revealedSection: @escaping () -> MenuBarSectionName?,
        reveal: @escaping (MenuBarSectionName?) -> Void,
        resetPresentation: @escaping () -> Void
    ) {
        self.activeDisplayID = activeDisplayID
        self.alwaysShow = alwaysShow
        self.usesThawBar = usesThawBar
        self.isZenModeActive = isZenModeActive
        self.revealedSection = revealedSection
        self.reveal = reveal
        self.resetPresentation = resetPresentation
    }

    deinit {
        observationTask?.cancel()
    }

    var isEnabled: Bool {
        guard !isZenModeActive(), let displayID = activeDisplayID() else { return false }
        return alwaysShow(displayID) && !usesThawBar(displayID)
    }

    /// Zen suspends the policy without transferring its reveal to the user. A reveal
    /// the policy owned goes back to the policy, which reveals inline again or resets;
    /// replayed as the user's, it could open the Thaw Bar with the Thaw Bar off.
    var shouldRestorePreZenReveals: Bool {
        !isAlwaysShowRevealActive
    }

    func observeDisplaySettings(
        _ readConfigurations: @escaping () -> [String: DisplayThawBarConfiguration],
        refreshControls: @escaping () -> Void
    ) {
        observationTask?.cancel()
        observationTask = Task { @MainActor [weak self] in
            let changes = Observations { readConfigurations() }
            for await _ in changes {
                guard let self else { return }
                synchronize()
                refreshControls()
            }
        }
    }

    /// Holds back from each screen-parameter posting until ``finishDisplayChange()``, or until a settle
    /// that changed nothing, so a reveal never lands on unsettled geometry.
    func holdDuringDisplayChanges(
        invalidations: some Publisher<Void, Never>,
        settlements: some Publisher<EnvironmentChange, Never>
    ) {
        displayChangeSubscriptions = [
            invalidations.sink { [weak self] in
                self?.displayChangeHold.invalidate()
            },
            settlements.sink { [weak self] change in
                guard let self, displayChangeHold.settle(change) else { return }
                apply(closingSections: false)
            },
        ]
    }

    /// The display change's presentation step, on the settled bar.
    func finishDisplayChange() {
        guard displayChangeHold.finishRun() else { return }
        apply(closingSections: false)
    }

    func synchronize(closingSections: Bool = false) {
        guard displayChangeHold.requestSync() else { return }
        apply(closingSections: closingSections)
    }

    private func apply(closingSections: Bool) {
        guard !isZenModeActive() else { return }
        let enabled = isEnabled
        guard enabled || isAlwaysShowRevealActive else { return }
        let current = revealedSection()
        let target = Self.targetSection(current: current, alwaysShow: enabled, closing: closingSections)
        if target != current {
            reveal(target)
        }
        isAlwaysShowRevealActive = enabled
        if !enabled {
            resetPresentation()
        }
    }

    private static nonisolated func targetSection(
        current: MenuBarSectionName?,
        alwaysShow: Bool,
        closing: Bool
    ) -> MenuBarSectionName? {
        guard alwaysShow else { return nil }
        return closing ? .hidden : current ?? .hidden
    }
}
