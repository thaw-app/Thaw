//
//  RehideController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import MenuBarModel

/// Owns the rehides that a focus change and a click outside the menu bar arm; callers only send it events.
///
/// The two rehides wait side by side, because one click can both change focus and land outside the bar.
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
        var now: @MainActor () -> ContinuousClock.Instant = { .now }
        var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    }

    enum Event {
        /// A click outside the menu bar; qualifies runs only under smart rehide, after its settings check.
        case outsideClick(qualifies: () -> Bool)
        case focusChanged
        /// A click, hover or scroll reveal, which drops a pending outside-click rehide.
        case inputReveal
    }

    /// Focus often changes on the reveal click itself, so a reveal this recent keeps the section.
    private static let revealGrace: Duration = .milliseconds(500)

    private let environment: Environment
    private let focusChangeRehide = TaskSlot()
    private let outsideClickRehide = TaskSlot()
    private var lastShow: ContinuousClock.Instant?
    private nonisolated let diagLog = DiagLog(category: "MenuBarManager")

    init(environment: Environment) {
        self.environment = environment
    }

    /// Call on every section reveal; it cancels a pending focus rehide but not an outside-click one.
    func revealed() {
        lastShow = environment.now()
        focusChangeRehide.cancel()
    }

    func note(_ event: Event) {
        switch event {
        case let .outsideClick(qualifies):
            armOutsideClickRehide(qualifies)
        case .focusChanged:
            armFocusChangeRehide()
        case .inputReveal:
            outsideClickRehide.cancel()
        }
    }

    /// Returns once neither rehide is waiting or running.
    func waitUntilIdle() async {
        await focusChangeRehide.waitUntilFinished()
        await outsideClickRehide.waitUntilFinished()
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
