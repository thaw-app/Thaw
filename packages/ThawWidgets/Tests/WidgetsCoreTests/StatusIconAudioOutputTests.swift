//
//  StatusIconAudioOutputTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Testing
@testable import WidgetsCore

/// The Bluetooth audio centre symbol: which output counts, and which symbol it gets.
@MainActor
@Suite("Status icon audio output")
struct StatusIconAudioOutputTests {
    @Test("A Bluetooth output is told apart by its transport, wired or built-in ones are not")
    func transportDecidesBluetooth() {
        #expect(AudioOutputSource.output(name: "AirPods Pro", transport: AudioOutputSource.bluetoothTransport)?.isBluetooth == true)
        #expect(AudioOutputSource.output(name: "Speaker", transport: AudioOutputSource.bluetoothLETransport)?.isBluetooth == true)
        #expect(AudioOutputSource.output(name: "MacBook Pro Speakers", transport: 0x626C_746E)?.isBluetooth == false)
        #expect(AudioOutputSource.output(name: nil, transport: AudioOutputSource.bluetoothTransport) == nil)
    }

    @Test("A device's name picks its symbol, with headphones for anything unrecognised", arguments: [
        ("AirPods Pro", "airpods.pro"),
        ("René’s AirPods Max", "airpods.max"),
        ("AirPods", "airpods"),
        ("Beats Studio Pro", "beats.headphones"),
        ("Living Room HomePod", "homepod"),
        ("JBL Flip Speaker", "hifispeaker"),
        ("WH-1000XM5", "headphones"),
    ])
    func symbolFromName(name: String, symbol: String) {
        #expect(StatusIconAudioOutput(name: name, isBluetooth: true).symbolName == symbol)
        #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "the symbol exists")
    }

    @Test("The Bluetooth centre shows the device while it plays through Bluetooth, and the network otherwise")
    func bluetoothCenterFallsBack() {
        var samples = StatusIconSamples(network: .wifi)
        #expect(StatusIconComposition.Center.bluetooth.symbolName(for: samples) == "wifi")
        samples.audioOutput = StatusIconAudioOutput(name: "AirPods Pro", isBluetooth: true)
        #expect(StatusIconComposition.Center.bluetooth.symbolName(for: samples) == "airpods.pro")
        #expect(StatusIconComposition.Center.bluetooth.showsNetwork(for: samples) == false)
        samples.audioOutput = StatusIconAudioOutput(name: "MacBook Pro Speakers", isBluetooth: false)
        #expect(StatusIconComposition.Center.bluetooth.symbolName(for: samples) == "wifi")
        #expect(StatusIconComposition.Center.bluetooth.showsNetwork(for: samples))
        #expect(!StatusIconComposition.Center.bluetooth.title.isEmpty)
    }

    @Test("Reading the default output gives nothing or a named output with a symbol, whatever this Mac plays through")
    func liveReadIsEmptyOrNamed() {
        // A Mac with no audio output (a CI runner, for one) reads nil, so only the named case is checked.
        guard let output = AudioOutputSource.defaultOutput() else { return }
        #expect(!output.name.isEmpty)
        #expect(NSImage(systemSymbolName: output.symbolName, accessibilityDescription: nil) != nil, "the symbol exists")
    }
}
