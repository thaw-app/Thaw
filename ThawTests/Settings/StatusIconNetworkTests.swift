//
//  StatusIconNetworkTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import Thaw

@MainActor
@Suite("Status icon network")
struct StatusIconNetworkTests {
    @Test("The center follows the used route, not the presence of a Wi-Fi radio")
    func activeRoute() {
        #expect(StatusIconNetwork(status: .satisfied, usedInterfaces: [.wiredEthernet]) == .ethernet)
        #expect(StatusIconNetwork(status: .satisfied, usedInterfaces: [.wifi]) == .wifi)
        #expect(StatusIconNetwork(status: .satisfied, usedInterfaces: [.cellular]) == .cellular)
        #expect(StatusIconNetwork(status: .satisfied, usedInterfaces: [.other]) == .other)
        #expect(StatusIconNetwork(status: .satisfied, usedInterfaces: []) == .other)
        #expect(StatusIconNetwork(status: .satisfied, usedInterfaces: [.wifi, .wiredEthernet]) == .ethernet)
        #expect(StatusIconNetwork(status: .unsatisfied, usedInterfaces: [.wifi]) == .disconnected)
        #expect(StatusIconNetwork(status: .requiresConnection, usedInterfaces: [.wiredEthernet]) == .disconnected)
    }

    @Test("Existing Wi-Fi recipes resolve each connection to a valid glyph", arguments: StatusIconNetwork.allCases)
    func connectionGlyph(network: StatusIconNetwork) throws {
        let center = try #require(StatusIconComposition.Center(rawValue: "wifi"))
        let samples = StatusIconSamples(network: network)
        guard network != .ethernet else {
            #expect(center.symbolName(for: samples) == nil, "Ethernet draws the custom packet glyph")
            return
        }
        let symbol = try #require(center.symbolName(for: samples))
        #expect(symbol == network.symbolName)
        #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
    }

    @Test("Decorative symbols do not change with the network")
    func decorativeSymbols() {
        let samples = StatusIconSamples(network: .ethernet)
        #expect(StatusIconComposition.Center.bolt.symbolName(for: samples) == "bolt.fill")
        #expect(StatusIconComposition.Center.none.symbolName(for: samples) == nil)
    }

    @Test("The click menu describes the same connection as the icon and offers Network Settings")
    func clickMenu() throws {
        let publisher = StatusItemPublisher()
        var state = StatusIconPreviewState(composition: .init(), samples: .init(network: .wifi), isLive: false)
        let initialMenu = publisher.makeMenu(for: state)
        state.samples.network = .ethernet
        state.isLive = true
        let updatedMenu = publisher.makeMenu(for: state)
        // NSMenuItem stores a no-break space, as in French "75 %", as a plain one.
        func plain(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        #expect(Array(updatedMenu.items.map(\.title).prefix(1 + state.details.count)).map(plain) == ([state.title] + state.details).map(plain))
        #expect(initialMenu.items.map(\.title) != updatedMenu.items.map(\.title))
        let action = try #require(updatedMenu.items.last)
        #expect(action.action != nil)
        #expect(action.target === publisher)
        #expect(action.isEnabled)
    }

    @Test("Ethernet and Wi-Fi produce different template images")
    func renderedConnectionChanges() throws {
        let wifi = StatusItemPublisher.render(CompositeStatusIcon(composition: .init(), samples: .init(network: .wifi)), size: 22)
        let ethernet = StatusItemPublisher.render(CompositeStatusIcon(composition: .init(), samples: .init(network: .ethernet)), size: 22)
        #expect(wifi.isTemplate && ethernet.isTemplate)
        #expect(wifi.size == NSSize(width: 22, height: 22))
        let wifiPixels = try #require(wifi.tiffRepresentation)
        let ethernetPixels = try #require(ethernet.tiffRepresentation)
        #expect(wifiPixels != ethernetPixels)
    }

    @Test("A center-only Wi-Fi symbol responds to signal strength")
    func wifiSignalChanges() throws {
        let composition = StatusIconComposition(outer: .none, center: .wifi, bottom: .none)
        var samples = StatusIconSamples(network: .wifi)
        samples.wifi = 0.05
        let weak = StatusItemPublisher.render(CompositeStatusIcon(composition: composition, samples: samples), size: 22)
        samples.wifi = 1
        let strong = StatusItemPublisher.render(CompositeStatusIcon(composition: composition, samples: samples), size: 22)
        let weakPixels = try #require(weak.tiffRepresentation)
        let strongPixels = try #require(strong.tiffRepresentation)
        #expect(weakPixels != strongPixels)
    }

    @Test("Center-only Wi-Fi exposes its reading but Ethernet does not invent a signal level")
    func centerOnlyReadings() {
        var state = StatusIconPreviewState(
            composition: .init(outer: .none, center: .wifi, bottom: .none),
            samples: .init(network: .wifi),
            isLive: true
        )
        #expect(state.sources == [.wifi])
        state.samples.network = .ethernet
        #expect(state.sources.isEmpty)
    }

    @Test("The live sampler resolves an initial network path")
    func liveNetworkPath() async throws {
        let sampler = StatusIconLiveSampler()
        sampler.start()
        defer { sampler.stop() }
        for _ in 0 ..< 20 where sampler.samples.network == .unknown {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(sampler.samples.network != .unknown)
    }

    @Test("Stopping the sampler prevents queued network updates")
    func stopSampling() async throws {
        let sampler = StatusIconLiveSampler()
        sampler.start()
        sampler.stop()
        let stopped = sampler.samples
        try await Task.sleep(for: .milliseconds(100))
        #expect(sampler.samples == stopped)
    }
}
