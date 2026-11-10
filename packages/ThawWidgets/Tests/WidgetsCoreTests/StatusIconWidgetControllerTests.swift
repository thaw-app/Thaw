//
//  StatusIconWidgetControllerTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
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

    @Test("A sample that changes nothing the icon shows is not published again")
    func unusedReadingsAreNotRepublished() throws {
        let controller = try makeController()
        var samples = StatusIconSamples(network: .wifi)
        controller.absorb(samples)
        let published = publisher.published.count

        samples.cpu = 0.9
        controller.absorb(samples)
        samples.battery += 0.001
        controller.absorb(samples)
        #expect(publisher.published.count == published, "the default icon shows battery and Wi-Fi, to the percent")

        samples.battery = 0.4
        controller.absorb(samples)
        #expect(publisher.published.count == published + 1)
        #expect(controller.liveSamples.cpu == 0.9, "the builder still gets every reading")
    }

    @Test("Manual mode stops the live sampler, and live mode starts it again")
    func manualModeStopsSampling() throws {
        let controller = try makeController()
        controller.setLive(true)
        #expect(!controller.isSampling, "nothing samples before the module starts")

        controller.start()
        #expect(controller.isSampling)
        controller.setLive(false)
        #expect(!controller.isSampling)
        controller.setLive(true)
        #expect(controller.isSampling)
        controller.setLive(false)
    }

    @Test("A module started in manual mode does not sample")
    func startInManualModeDoesNotSample() throws {
        let controller = try makeController()
        controller.setLive(false)
        controller.start()
        #expect(!controller.isSampling)
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

    @Test("The icon's size, thickness and status colours come back from settings, with defaults first")
    func storedStyle() throws {
        let controller = try makeController()
        #expect(controller.currentState().style == StatusIconStyle())
        controller.defaults.set(StatusIconStyle.Size.large.rawValue, forKey: WidgetKeys.size)
        controller.defaults.set(StatusIconStyle.Thickness.thick.rawValue, forKey: WidgetKeys.thickness)
        controller.defaults.set(false, forKey: WidgetKeys.statusColors)
        let style = controller.currentState().style
        #expect(style == StatusIconStyle(size: .large, thickness: .thick, statusColors: false))
    }
}

@MainActor
@Suite("Status item rendering")
struct StatusItemRenderingTests {
    @Test("The menu bar image is a template unless a reading in it is coloured")
    func templateUnlessColored() {
        var samples = StatusIconSamples()
        samples.battery = 0.9
        var state = StatusIconPreviewState(composition: StatusIconComposition(), samples: samples, isLive: true)
        #expect(StatusItemPublisher.image(for: state, darkMenuBar: false).isTemplate)
        state.samples.isCharging = true
        let colored = StatusItemPublisher.image(for: state, darkMenuBar: true)
        #expect(!colored.isTemplate)
        #expect(colored.size == CGSize(width: 22, height: 22))
    }

    @Test("An appearance set again without changing, as AppKit does to snapshot the item, redraws nothing")
    func sameAppearanceRedrawsNothing() {
        let publisher = StatusItemPublisher()
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        var samples = StatusIconSamples()
        samples.isCharging = true
        publisher.lastState = StatusIconPreviewState(composition: StatusIconComposition(), samples: samples, isLive: true)
        button.appearance = NSAppearance(named: .darkAqua)
        publisher.appearanceChanged(of: button)
        let drawn = button.image

        publisher.appearanceChanged(of: button)
        #expect(button.image === drawn)

        button.appearance = NSAppearance(named: .aqua)
        publisher.appearanceChanged(of: button)
        #expect(button.image !== drawn)
    }

    @Test("A template icon is left alone when the menu bar turns light or dark")
    func templateIsNotRedrawn() {
        let publisher = StatusItemPublisher()
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        publisher.lastState = StatusIconPreviewState(composition: StatusIconComposition(), samples: StatusIconSamples(), isLive: true)
        button.appearance = NSAppearance(named: .darkAqua)
        publisher.appearanceChanged(of: button)
        #expect(button.image == nil)
    }

    @Test("A reading that changes its text and not its picture leaves the drawn content equal")
    func textOnlyChangesDrawNothingNew() {
        var samples = StatusIconSamples(network: .wifi)
        samples.wifi = 0.80
        let state = StatusIconPreviewState(composition: StatusIconComposition(), samples: samples, isLive: true)
        var nudged = state
        nudged.samples.wifi = 0.81
        #expect(nudged.displayed != state.displayed, "the menu says 81%")
        #expect(nudged.drawn == state.drawn, "the same bars and dots are lit")

        var weaker = state
        weaker.samples.wifi = 0.2
        #expect(weaker.drawn != state.drawn)
        var charged = state
        charged.samples.battery = 0.5
        #expect(charged.drawn != state.drawn)
    }

    @Test("A coloured icon is redrawn when the menu bar turns light or dark")
    func redrawsOnAppearanceChange() {
        let publisher = StatusItemPublisher()
        let button = NSButton(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        var samples = StatusIconSamples()
        samples.isCharging = true
        publisher.lastState = StatusIconPreviewState(composition: StatusIconComposition(), samples: samples, isLive: true)
        let observation = publisher.observeAppearance(of: button)
        defer { observation.invalidate() }
        button.appearance = NSAppearance(named: .darkAqua)
        #expect(button.image != nil)
        #expect(button.image?.isTemplate == false)
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
