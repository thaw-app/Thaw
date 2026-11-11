//
//  BarSettlingObservers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine
import MenuBarModel

/// Reports screen wakes, display invalidations and revealed-section changes to a BarSettling, each in
/// the turn it is posted, so a hold starts at the change and not after whatever the main thread does next.
@MainActor
final class BarSettlingObservers {
    private let settling: BarSettling
    private var wakeTask: Task<Void, Never>?
    private var displayInvalidation: AnyCancellable?
    private var revealedSection: AnyCancellable?

    /// Observes screen wakes from the start; the other sources arrive through observe calls.
    init(settling: BarSettling, observesScreenWakes: Bool = true) {
        self.settling = settling
        guard observesScreenWakes else { return }
        wakeTask = NSWorkspace.shared.notificationCenter.eventsTask(named: NSWorkspace.screensDidWakeNotification) { [weak settling] in
            settling?.note(.screensWoke)
        }
    }

    /// A later call replaces the earlier source.
    func observe(displayInvalidations: some Publisher<Void, Never>) {
        displayInvalidation = displayInvalidations.sink { [weak settling] in settling?.note(.displaysInvalidated) }
    }

    /// The first value is the current section, not a change. A later call replaces the earlier source.
    func observe(revealedSections: AnyPublisher<MenuBarSectionName?, Never>) {
        revealedSection = revealedSections
            .dropFirst()
            .sink { [weak settling] _ in settling?.note(.revealedSectionChanged) }
    }
}
