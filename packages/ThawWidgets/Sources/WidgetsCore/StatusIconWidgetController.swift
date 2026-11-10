//
//  StatusIconWidgetController.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import SwiftUI

/// Where the widget icon is drawn: the menu bar in the app, a stand-in in tests.
@MainActor
protocol StatusIconPublishing: AnyObject {
    func publish(_ state: StatusIconPreviewState)
}

extension StatusItemPublisher: StatusIconPublishing {}

/// Keeps the widget icon in the menu bar while the module runs, fed by the
/// sampler, and remembers what the builder window chose.
@MainActor
@Observable
final class StatusIconWidgetController {
    static let shared = StatusIconWidgetController()

    /// The sampler's latest readings. Volume is manual and never lives here.
    var liveSamples = StatusIconSamples(network: .unknown)

    let defaults: UserDefaults
    private let publisher: any StatusIconPublishing
    private let sampler = StatusIconLiveSampler()
    private var samplerCancellable: AnyCancellable?
    private var isStarted = false
    private var lastPublished: StatusIconDisplayedContent?

    /// Whether the live sampler is polling. Manual mode shows the sliders' values, so it stops.
    var isSampling: Bool {
        sampler.isRunning
    }

    init(defaults: UserDefaults = .standard, publisher: any StatusIconPublishing = StatusItemPublisher.shared) {
        self.defaults = defaults
        self.publisher = publisher
    }

    /// Puts the icon in the menu bar and starts the sampler. Running is what
    /// "on" means for this module, so there is no matching stop.
    func start() {
        isStarted = true
        if isLive {
            sampler.start()
        }
        if samplerCancellable == nil {
            samplerCancellable = sampler.$samples
                .removeDuplicates()
                .sink { [weak self] samples in self?.absorb(samples) }
        }
        republish()
    }

    /// Receives one sampler delivery: updates the published live readings and
    /// re-renders the menu bar item from the merged state.
    func absorb(_ samples: StatusIconSamples) {
        liveSamples = samples
        republish()
    }

    /// Shows what the builder window shows. Only manual readings are saved,
    /// so live ones never replace the values the sliders come back to.
    func refresh(with state: StatusIconPreviewState) {
        if !state.isLive, let data = try? JSONEncoder().encode(state.samples) {
            defaults.set(data, forKey: WidgetKeys.samples)
        }
        publish(state)
    }

    /// The manual readings last used in the builder, restored for the sliders.
    func storedSamples() -> StatusIconSamples {
        guard let data = defaults.data(forKey: WidgetKeys.samples),
              let samples = try? JSONDecoder().decode(StatusIconSamples.self, from: data)
        else { return StatusIconSamples() }
        return samples
    }

    var isLive: Bool {
        defaults.object(forKey: WidgetKeys.live) as? Bool ?? true
    }

    func setLive(_ newValue: Bool) {
        defaults.set(newValue, forKey: WidgetKeys.live)
        guard isStarted else { return }
        if newValue {
            sampler.start()
        } else {
            sampler.stop()
        }
    }

    private func republish() {
        publish(currentState())
    }

    /// Redraws the icon only when what it shows changed: most samples differ in a reading it doesn't use.
    private func publish(_ state: StatusIconPreviewState) {
        let content = state.displayed
        guard content != lastPublished else { return }
        lastPublished = content
        publisher.publish(state)
    }

    /// Rebuilds the snapshot from defaults and the sampler.
    func currentState() -> StatusIconPreviewState {
        let manual = storedSamples()
        var samples = isLive ? liveSamples : manual
        samples.volume = manual.volume
        return StatusIconPreviewState(composition: storedComposition(), samples: samples, isLive: isLive, style: storedStyle())
    }

    private func storedStyle() -> StatusIconStyle {
        let fallback = StatusIconStyle()
        return StatusIconStyle(
            size: decode(WidgetKeys.size, fallback: fallback.size),
            thickness: decode(WidgetKeys.thickness, fallback: fallback.thickness),
            statusColors: defaults.object(forKey: WidgetKeys.statusColors) as? Bool ?? fallback.statusColors
        )
    }

    /// A saved option, or fallback when it's missing or this version doesn't know it.
    private func decode<T: RawRepresentable>(_ key: String, fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap { T(rawValue: $0) } ?? fallback
    }

    private func storedComposition() -> StatusIconComposition {
        let defaultRecipe = StatusIconComposition()
        return StatusIconComposition(
            outer: decode(WidgetKeys.outer, fallback: defaultRecipe.outer),
            outerSource: decode(WidgetKeys.outerSource, fallback: defaultRecipe.outerSource),
            center: decode(WidgetKeys.center, fallback: defaultRecipe.center),
            bottom: decode(WidgetKeys.bottom, fallback: defaultRecipe.bottom),
            bottomSource: decode(WidgetKeys.bottomSource, fallback: defaultRecipe.bottomSource)
        )
    }
}
