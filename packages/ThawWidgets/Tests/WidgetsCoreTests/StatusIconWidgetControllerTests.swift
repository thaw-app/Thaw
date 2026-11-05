//
//  StatusIconWidgetControllerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
import ThawModuleTestSupport
@testable import WidgetsCore

/// Records what the controller would put in the menu bar, so tests never
/// add a real status item.
@MainActor
final class RecordingPublisher: StatusIconPublishing {
    var published: [StatusIconPreviewState] = []

    func publish(_ state: StatusIconPreviewState) {
        published.append(state)
    }
}

@MainActor
@Suite("Status icon widget controller")
struct StatusIconWidgetControllerTests {
    private let suites = ScratchSuites(prefix: "StatusIconWidgetControllerTests")
    private let publisher = RecordingPublisher()

    private func makeController() throws -> StatusIconWidgetController {
        try StatusIconWidgetController(defaults: #require(suites.make()), publisher: publisher)
    }

    @Test("Sampler readings flow into live samples and the published icon")
    func samplerFeedsLiveSamples() throws {
        let controller = try makeController()
        #expect(controller.liveSamples.network == .unknown, "Before the first sampler delivery")

        controller.absorb(StatusIconSamples(network: .ethernet, wifi: 0.3))

        #expect(controller.liveSamples.network == .ethernet)
        #expect(publisher.published.last?.samples.network == .ethernet, "The icon must match the sampler")
    }

    @Test("Manual readings are saved and come back for the sliders")
    func manualSamplesPersist() throws {
        let controller = try makeController()
        var samples = StatusIconSamples(network: .ethernet)
        samples.battery = 0.4
        samples.volume = 0.9
        let state = StatusIconPreviewState(
            composition: StatusIconComposition(outer: .ring, outerSource: .volume, center: .none, bottom: .none),
            samples: samples,
            isLive: false
        )
        controller.refresh(with: state)
        #expect(controller.storedSamples() == samples)
        #expect(publisher.published.last == state)
    }

    @Test("Live readings don't replace the saved manual ones")
    func liveSamplesAreNotSaved() throws {
        let controller = try makeController()
        var manual = StatusIconSamples(network: .cellular)
        manual.battery = 0.2
        controller.refresh(with: StatusIconPreviewState(composition: .init(), samples: manual, isLive: false))

        controller.refresh(with: StatusIconPreviewState(composition: .init(), samples: StatusIconSamples(network: .wifi), isLive: true))

        #expect(controller.storedSamples() == manual)
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
}

@MainActor
@Suite("Widget settings import")
struct WidgetSettingsImportTests {
    private let suites = ScratchSuites(prefix: "WidgetSettingsImportTests")

    @Test("The first run copies Thaw's widget settings and nothing else")
    func copiesWidgetKeys() throws {
        let host = try #require(suites.make())
        host.set("ring", forKey: "StatusIconPrototype.outer")
        host.set(true, forKey: "StatusIconPrototype.published")
        host.set("unrelated", forKey: "SomeOtherSetting")
        let store = try #require(suites.make())

        WidgetSettingsImport.importFromThaw(into: store, hostDefaults: host)

        #expect(store.string(forKey: "StatusIconPrototype.outer") == "ring")
        #expect(store.bool(forKey: "StatusIconPrototype.published"))
        #expect(store.string(forKey: "SomeOtherSetting") == nil)
    }

    @Test("Later runs keep the module's own changes")
    func importsOnce() throws {
        let host = try #require(suites.make())
        host.set("ring", forKey: "StatusIconPrototype.outer")
        let store = try #require(suites.make())
        WidgetSettingsImport.importFromThaw(into: store, hostDefaults: host)
        store.set("arc", forKey: "StatusIconPrototype.outer")

        WidgetSettingsImport.importFromThaw(into: store, hostDefaults: host)

        #expect(store.string(forKey: "StatusIconPrototype.outer") == "arc")
    }
}
