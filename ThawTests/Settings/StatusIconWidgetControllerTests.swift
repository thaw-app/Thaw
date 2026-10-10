//
//  StatusIconWidgetControllerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@MainActor
@Suite("Status icon widget controller", .serialized)
struct StatusIconWidgetControllerTests {
    private func makeController() throws -> StatusIconWidgetController {
        let suiteName = "StatusIconWidgetControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return StatusIconWidgetController(defaults: defaults)
    }

    @Test("Sampler readings flow into live samples and the published state")
    func samplerFeedsLiveSamples() throws {
        let controller = try makeController()
        controller.setEnabled(true)
        defer { StatusItemPublisher.shared.hide() }
        #expect(controller.liveSamples.network == .unknown, "Before the first sampler delivery")

        controller.absorb(StatusIconSamples(network: .ethernet, wifi: 0.3))

        #expect(controller.liveSamples.network == .ethernet)
        #expect(controller.currentState().samples.network == .ethernet, "The published snapshot must match the sampler")
    }

    @Test("Enabling persists the flag and republishes; disabling hides and clears it")
    func enableDisable() throws {
        let controller = try makeController()
        defer { StatusItemPublisher.shared.hide() }
        #expect(!controller.isEnabled)
        controller.setEnabled(true)
        #expect(controller.isEnabled)
        #expect(controller.defaults.bool(forKey: "StatusIconPrototype.published"))
        #expect(StatusItemPublisher.shared.isPublished)
        controller.setEnabled(false)
        #expect(!StatusItemPublisher.shared.isPublished)
        #expect(!controller.defaults.bool(forKey: "StatusIconPrototype.published"))
    }

    @Test("A fresh controller restores an item that was left enabled")
    func restoreAtLaunch() throws {
        let controller = try makeController()
        defer { StatusItemPublisher.shared.hide() }
        controller.setEnabled(true)
        StatusItemPublisher.shared.hide()

        let relaunched = StatusIconWidgetController(defaults: controller.defaults)
        #expect(relaunched.isEnabled)
        relaunched.restore()
        #expect(StatusItemPublisher.shared.isPublished)
    }

    @Test("Refresh persists the samples the pane showed and reuses them for the sliders")
    func samplePersistence() throws {
        let controller = try makeController()
        defer { StatusItemPublisher.shared.hide() }
        var samples = StatusIconSamples(network: .ethernet)
        samples.battery = 0.4
        samples.volume = 0.9
        let state = StatusIconPreviewState(
            composition: StatusIconComposition(outer: .ring, outerSource: .volume, center: .none, bottom: .none),
            samples: samples,
            isLive: false
        )
        controller.setEnabled(true)
        controller.refresh(with: state)
        let restored = controller.storedSamples()
        #expect(restored == samples)
    }

    @Test("The current state decodes the stored recipe and merges manual volume into live readings")
    func currentStateMerging() throws {
        let controller = try makeController()
        controller.defaults.set(StatusIconComposition.Outer.ring.rawValue, forKey: "StatusIconPrototype.outer")
        controller.defaults.set(StatusIconComposition.Center.moon.rawValue, forKey: "StatusIconPrototype.center")
        controller.defaults.set(false, forKey: "StatusIconPrototype.live")
        var manual = StatusIconSamples(network: .cellular)
        manual.volume = 0.62
        try controller.defaults.set(JSONEncoder().encode(manual), forKey: "StatusIconPrototype.samples")

        controller.liveSamples = StatusIconSamples(network: .wifi, volume: 0.1)
        let state = controller.currentState()
        #expect(state.composition.outer == .ring)
        #expect(state.composition.center == .moon)
        #expect(!state.isLive)
        #expect(state.samples.network == .cellular, "Manual mode uses the stored connection")
        #expect(state.samples.volume == 0.62)

        controller.setLive(true)
        let liveState = controller.currentState()
        #expect(liveState.isLive)
        #expect(liveState.samples.network == .wifi, "Live mode uses the sampler's connection")
        #expect(liveState.samples.volume == 0.62, "Volume stays manual in live mode")
    }

    @Test("Refresh is inert while the item is disabled")
    func refreshWhenDisabled() throws {
        let controller = try makeController()
        let state = StatusIconPreviewState(composition: .init(), samples: .init(), isLive: true)
        controller.refresh(with: state)
        #expect(controller.defaults.data(forKey: "StatusIconPrototype.samples") == nil)
        #expect(!StatusItemPublisher.shared.isPublished)
    }
}
