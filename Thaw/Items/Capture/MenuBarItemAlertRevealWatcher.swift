//
//  MenuBarItemAlertRevealWatcher.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import MenuBarModel
import ThawModuleKit

// MARK: - MenuBarItemAlertReveals

/// Defaults-backed store of the items the user opted into revealing when
/// their icon changes, keyed by MenuBarItemTag.tagIdentifier.
@MainActor
enum MenuBarItemAlertReveals {
    static func identifiers() -> Set<String> {
        Set(Defaults.stringArray(forKey: .menuBarItemAlertReveals) ?? [])
    }

    /// The items to watch: the saved choice while Triggers is on, none while it is off.
    static func watched(saved: Set<String>, triggersOn: Bool) -> Set<String> {
        triggersOn ? saved : []
    }

    static func contains(_ identifier: String) -> Bool {
        identifiers().contains(identifier)
    }

    static func setEnabled(_ enabled: Bool, for identifier: String) {
        var current = identifiers()
        if enabled {
            current.insert(identifier)
        } else {
            current.remove(identifier)
        }
        Defaults.set(current.sorted(), forKey: .menuBarItemAlertReveals)
    }
}

// MARK: - AlertRevealPolicy

/// Pure decision logic for whether an icon change should reveal an item,
/// kept separate from the watcher so the throttling is unit-testable.
nonisolated struct AlertRevealPolicy {
    /// The minimum time between reveals of the same item, so an icon that
    /// animates continuously can't bounce its item in and out of the bar.
    var cooldown = Duration.seconds(45)

    private(set) var lastReveals: [String: ContinuousClock.Instant] = [:]

    /// Returns whether identifier may reveal now, recording the reveal
    /// instant when it may.
    mutating func shouldReveal(_ identifier: String, now: ContinuousClock.Instant) -> Bool {
        if let last = lastReveals[identifier], last.duration(to: now) < cooldown {
            return false
        }
        lastReveals[identifier] = now
        return true
    }
}

// MARK: - MenuBarItemAlertRevealWatcher

/// Temporarily reveals concealed items when their captured icon changes,
/// the "surface the item only when it's alerting" behavior. Piggybacks on
/// the image cache's capture stream, so it adds no captures of its own,
/// and reuses the section controller's temporary-reveal path (macOS 27).
@MainActor
final class MenuBarItemAlertRevealWatcher {
    private let diagLog = DiagLog(category: "MenuBarItemAlertRevealWatcher")

    /// The last-seen image per opted-in identifier. The first sighting only
    /// seeds the baseline; reveals require a change against it.
    private var baselines: [String: MenuBarItemGlyphCapture] = [:]

    private var policy = AlertRevealPolicy()
    private var cancellables = Set<AnyCancellable>()

    private(set) weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        // MenuBarItemImageCache is @Observable, so captures arrive through
        // an Observations sequence.
        let task = Task { @MainActor [weak self, imageCache = appState.imageCache] in
            let changes = Observations { imageCache.capturesByTag }
            for await images in changes {
                guard let self else { return }
                process(images)
            }
        }
        AnyCancellable { task.cancel() }
            .store(in: &cancellables)
    }

    private func process(_ images: [MenuBarItemTag: MenuBarItemGlyphCapture]) {
        // Before setup this is an InertSectionController, whose reveal calls
        // are no-ops, so no extra guard is needed here.
        process(
            images,
            sectionController: appState?.menuBarManager.sectionController,
            triggersOn: appState?.moduleHost.isEnabled(.triggers) ?? false
        )
    }

    /// Compares images against the baselines and reveals what changed, through
    /// sectionController; nil, as when the app state is gone, reveals nothing.
    func process(
        _ images: [MenuBarItemTag: MenuBarItemGlyphCapture],
        sectionController: (any MenuBarSectionControlling)?,
        triggersOn: Bool = true,
        now: ContinuousClock.Instant = .now
    ) {
        // Icon changes are one of the triggers, so they stop with the Triggers module.
        let enabled = MenuBarItemAlertReveals.watched(
            saved: MenuBarItemAlertReveals.identifiers(),
            triggersOn: triggersOn
        )
        guard !enabled.isEmpty else {
            baselines.removeAll()
            return
        }
        guard let sectionController else {
            return
        }
        for (tag, image) in images {
            let identifier = tag.tagIdentifier
            guard enabled.contains(identifier) else {
                continue
            }
            let baseline = baselines[identifier]
            baselines[identifier] = image
            guard let baseline, !MenuBarItemGlyphCapture.isVisuallyEqual(baseline, image) else {
                continue
            }
            // Only concealed items need surfacing; a visible item's icon
            // change is already on screen.
            guard let section = sectionController.sectionAssignment[identifier], section != .visible else {
                continue
            }
            guard policy.shouldReveal(identifier, now: now) else {
                continue
            }
            diagLog.info("Icon change detected for \(identifier); revealing temporarily")
            sectionController.revealItemTemporarily(identifier)
            sectionController.scheduleTemporaryItemConcealUnlessHeld(identifier)
        }

        // Forget baselines for items that are no longer opted in or present.
        baselines = baselines.filter { enabled.contains($0.key) }
    }
}
