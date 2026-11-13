//
//  RehideController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Owns every rehide timer: one per revealed section, one for focus changes and one for outside clicks.
///
/// They wait side by side, because one click can both change focus and land outside the bar.
@MainActor
final class RehideController {
    struct Settings: Equatable {
        var autoRehide: Bool
        var strategy: RehideStrategy
        var interval: TimeInterval
    }

    /// What the controller reads and does, so tests can run it without a menu bar.
    struct Environment {
        var settings: @MainActor () -> Settings
        var isAnyMenuOpen: @MainActor () async -> Bool
        /// False when no screen has a menu bar to check.
        var isPointerAwayFromBars: @MainActor () -> Bool
        var activeSpaceID: @MainActor () -> CGSSpaceID
        /// Whether the window under the pointer belongs to the active regular app or the Dock.
        var isPointerOverFrontmostApp: @MainActor () -> Bool
        var hideHiddenSection: @MainActor () -> Void
        var hideEverySection: @MainActor () -> Void
        /// The hover band under every menu bar or the Thaw Bar, unlike the strip that isPointerAwayFromBars checks.
        var isPointerInActiveArea: @MainActor () -> Bool
        var hideSection: @MainActor (MenuBarSection.Name) -> Void
        var startPointerMonitor: @MainActor (MenuBarSection.Name, @escaping @MainActor () -> Void) -> Void
        var stopPointerMonitor: @MainActor (MenuBarSection.Name) -> Void
        var now: @MainActor () -> ContinuousClock.Instant = { .now }
        var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    }

    enum Event {
        /// A click outside the menu bar; qualifies runs only under smart rehide, after its settings check.
        case outsideClick(qualifies: () -> Bool)
        case focusChanged
        /// A click, hover or scroll reveal, which drops a pending outside-click rehide.
        case inputReveal
        case pointerMoved(MenuBarSection.Name)
    }

    /// Focus often changes on the reveal click itself, so a reveal this recent keeps the section.
    private static let revealGrace: Duration = .milliseconds(500)

    private let environment: Environment
    private let focusChangeRehide = TaskSlot()
    private let outsideClickRehide = TaskSlot()
    private var lastShow: ContinuousClock.Instant?
    /// A finished task stays here until replaced, so the timed countdown counts it as still running.
    private var sectionRehides: [MenuBarSection.Name: Task<Void, Never>] = [:]
    private nonisolated let diagLog = DiagLog(category: "MenuBarManager")
    private nonisolated let sectionLog = DiagLog(category: "MenuBarSection")

    init(environment: Environment) {
        self.environment = environment
    }

    /// Call when a section reveal starts; it cancels a pending focus rehide but not an outside-click one.
    func revealed() {
        lastShow = environment.now()
        focusChangeRehide.cancel()
    }

    /// Call once the section is presented; it restarts that section's rehide from scratch.
    func revealed(_ section: MenuBarSection.Name) {
        startSectionRehide(section)
    }

    /// Hiding any section closes every revealed section, so none may keep a countdown or pointer monitor.
    func hidden(_: MenuBarSection.Name) {
        for section in MenuBarSection.Name.allCases {
            sectionRehides[section]?.cancel()
            environment.stopPointerMonitor(section)
        }
        sectionRehides.removeAll()
    }

    func note(_ event: Event) {
        switch event {
        case let .outsideClick(qualifies):
            armOutsideClickRehide(qualifies)
        case .focusChanged:
            armFocusChangeRehide()
        case .inputReveal:
            outsideClickRehide.cancel()
        case let .pointerMoved(section):
            updateTimedRehide(section)
        }
    }

    /// Returns once the rehides pending at the call have finished; a section restart begun meanwhile is not awaited.
    func waitUntilIdle() async {
        await focusChangeRehide.waitUntilFinished()
        await outsideClickRehide.waitUntilFinished()
        for task in Array(sectionRehides.values) {
            await task.value
        }
    }

    // MARK: Section rehides

    private func startSectionRehide(_ section: MenuBarSection.Name) {
        sectionRehides[section]?.cancel()
        sectionRehides[section] = nil
        environment.stopPointerMonitor(section)

        let settings = environment.settings()
        guard settings.autoRehide else { return }
        switch settings.strategy {
        case .smart:
            // A fallback for when no outside click comes.
            sectionRehides[section] = makeSectionRehide(section, interval: settings.interval) { [weak self] in
                self?.startSectionRehide(section)
            }
        case .timed:
            environment.startPointerMonitor(section) { [weak self] in
                self?.note(.pointerMoved(section))
            }
            // A reveal may be followed by no movement at all, so the countdown starts now.
            updateTimedRehide(section)
        case .focusedApp:
            break
        }
    }

    private func updateTimedRehide(_ section: MenuBarSection.Name) {
        let step = TimedRehideStep.next(
            pointerInBar: environment.isPointerInActiveArea(),
            countdownRunning: sectionRehides[section] != nil
        )
        switch step {
        case .start:
            sectionRehides[section] = makeSectionRehide(section, interval: environment.settings().interval) { [weak self] in
                self?.sectionLog.debug("Open menu detected - restarting timed rehide task")
                self?.restartTimedRehide(section)
            }
        case .cancel:
            sectionRehides[section]?.cancel()
            sectionRehides[section] = nil
        case .keep:
            break
        }
    }

    private func restartTimedRehide(_ section: MenuBarSection.Name) {
        let settings = environment.settings()
        guard settings.autoRehide, settings.strategy == .timed else { return }
        sectionRehides[section]?.cancel()
        sectionRehides[section] = makeSectionRehide(section, interval: settings.interval) { [weak self] in
            self?.sectionLog.debug("Open menu still detected - restarting timed rehide task again")
            self?.restartTimedRehide(section)
        }
    }

    /// After a full eligible interval, the pointer in the area restarts the checks and an open menu defers to onOpenMenu.
    private func makeSectionRehide(
        _ section: MenuBarSection.Name,
        interval: TimeInterval,
        onOpenMenu: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self, await waitForContinuousEligibility(interval: interval) else { return }
            if environment.isPointerInActiveArea() {
                startSectionRehide(section)
                return
            }
            let menuOpen = await environment.isAnyMenuOpen()
            // A pointer move or a fresh reveal can cancel this task while it waits on the answer.
            guard !Task.isCancelled else { return }
            if menuOpen {
                onOpenMenu()
                return
            }
            environment.hideSection(section)
        }
    }

    /// Time with a menu open does not count, so a menu choice is not followed by an immediate collapse.
    private func waitForContinuousEligibility(interval: TimeInterval) async -> Bool {
        var eligibleSince = environment.now()
        while !Task.isCancelled {
            try? await environment.sleep(.milliseconds(250))
            guard !Task.isCancelled else { return false }
            if environment.isPointerInActiveArea() {
                return false
            }
            if await environment.isAnyMenuOpen() {
                eligibleSince = environment.now()
                continue
            }
            if eligibleSince.duration(to: environment.now()) >= .seconds(interval) {
                return true
            }
        }
        return false
    }

    private func armFocusChangeRehide() {
        let settings = environment.settings()
        guard settings.autoRehide else { return }
        switch settings.strategy {
        case .focusedApp, .smart:
            break
        case .timed:
            return
        }
        // The user is still using the bars while the pointer is over one of them.
        guard environment.isPointerAwayFromBars() else { return }
        focusChangeRehide.replace { [weak self] _ in
            await self?.rehideAfterFocusChange(interval: settings.interval)
        }
    }

    private func rehideAfterFocusChange(interval: TimeInterval) async {
        do {
            try await environment.sleep(.seconds(interval))
        } catch {
            return
        }
        // A reveal can cancel this task even after the sleep returns.
        guard !Task.isCancelled else { return }

        if let lastShow, lastShow.duration(to: environment.now()) < Self.revealGrace {
            diagLog.debug("Skipping rehide due to grace period")
            return
        }
        if environment.settings().strategy == .smart, await environment.isAnyMenuOpen() {
            return
        }
        environment.hideHiddenSection()
    }

    private func armOutsideClickRehide(_ qualifies: () -> Bool) {
        let settings = environment.settings()
        guard settings.autoRehide, settings.strategy == .smart, qualifies() else { return }
        let spaceAtClick = environment.activeSpaceID()
        outsideClickRehide.replace { [weak self] _ in
            await self?.rehideAfterOutsideClick(interval: settings.interval, spaceAtClick: spaceAtClick)
        }
    }

    /// Every condition is checked again after the wait, not trusted from click time.
    private func rehideAfterOutsideClick(interval: TimeInterval, spaceAtClick: CGSSpaceID) async {
        do {
            try await environment.sleep(.seconds(interval))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        // A click that moved to another space settles it; the window under the pointer belongs to the new one.
        if environment.activeSpaceID() != spaceAtClick {
            environment.hideEverySection()
            return
        }
        guard environment.isPointerOverFrontmostApp() else { return }
        if await environment.isAnyMenuOpen() {
            return
        }
        guard !Task.isCancelled else { return }
        environment.hideEverySection()
    }
}
