//
//  StatusIconWidgetController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import SwiftUI

/// Owns the widget preview item's life above the settings pane.
///
/// Persists the enabled flag, restores the item on launch, and runs the
/// sampler app-wide. The pane only edits the recipe through refresh(with:).
@MainActor
@Observable
final class StatusIconWidgetController {
    static let shared = StatusIconWidgetController()

    private(set) var isEnabled: Bool
    /// The sampler's latest readings. Volume is manual and never lives here.
    var liveSamples = StatusIconSamples(network: .unknown)

    let defaults: UserDefaults
    private let sampler = StatusIconLiveSampler()
    private var samplerCancellable: AnyCancellable?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.Keys.enabled)
    }

    private enum Keys {
        static let enabled = "StatusIconPrototype.published"
        static let live = "StatusIconPrototype.live"
        static let samples = "StatusIconPrototype.samples"
        static let outer = "StatusIconPrototype.outer"
        static let outerSource = "StatusIconPrototype.outerSource"
        static let center = "StatusIconPrototype.center"
        static let bottom = "StatusIconPrototype.bottom"
        static let bottomSource = "StatusIconPrototype.bottomSource"
    }

    // MARK: Lifecycle

    /// Enables or disables the menu bar item. The flag persists so the next
    /// launch can restore the item without the pane being opened first.
    func setEnabled(_ newValue: Bool) {
        guard newValue != isEnabled else { return }
        isEnabled = newValue
        defaults.set(newValue, forKey: Self.Keys.enabled)
        if newValue {
            start()
            republish()
        } else {
            stop()
            StatusItemPublisher.shared.hide()
        }
    }

    /// Restores the item at launch. A no-op while disabled.
    func restore() {
        guard isEnabled else { return }
        start()
        republish()
    }

    private func start() {
        sampler.start()
        guard samplerCancellable == nil else { return }
        samplerCancellable = sampler.$samples
            .removeDuplicates()
            .sink { [weak self] samples in self?.absorb(samples) }
    }

    /// Receives one sampler delivery: updates the published live readings and
    /// re-renders the menu bar item from the merged state.
    func absorb(_ samples: StatusIconSamples) {
        liveSamples = samples
        republish()
    }

    private func stop() {
        samplerCancellable?.cancel()
        samplerCancellable = nil
        sampler.stop()
    }

    // MARK: State

    /// The pane's current preview: stored alongside the recipe so the
    /// controller's own re-publishes render exactly what the pane showed.
    func refresh(with state: StatusIconPreviewState) {
        guard isEnabled else { return }
        if let data = try? JSONEncoder().encode(state.samples) {
            defaults.set(data, forKey: Self.Keys.samples)
        }
        StatusItemPublisher.shared.publish(state)
    }

    /// The manual readings last used on the pane, restored for the sliders.
    func storedSamples() -> StatusIconSamples {
        guard let data = defaults.data(forKey: Self.Keys.samples),
              let samples = try? JSONDecoder().decode(StatusIconSamples.self, from: data)
        else { return StatusIconSamples() }
        return samples
    }

    var isLive: Bool {
        defaults.object(forKey: Self.Keys.live) as? Bool ?? true
    }

    func setLive(_ newValue: Bool) {
        defaults.set(newValue, forKey: Self.Keys.live)
    }

    private func republish() {
        StatusItemPublisher.shared.publish(currentState())
    }

    /// Rebuilds the snapshot from defaults and the sampler.
    func currentState() -> StatusIconPreviewState {
        let manual = storedSamples()
        var samples = isLive ? liveSamples : manual
        samples.volume = manual.volume
        return StatusIconPreviewState(composition: storedComposition(), samples: samples, isLive: isLive)
    }

    private func storedComposition() -> StatusIconComposition {
        func decode<T: RawRepresentable>(_ key: String, fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap { T(rawValue: $0) } ?? fallback
        }
        return StatusIconComposition(
            outer: decode(Self.Keys.outer, fallback: .arc),
            outerSource: decode(Self.Keys.outerSource, fallback: .battery),
            center: decode(Self.Keys.center, fallback: .wifi),
            bottom: decode(Self.Keys.bottom, fallback: .dots),
            bottomSource: decode(Self.Keys.bottomSource, fallback: .wifi)
        )
    }
}
