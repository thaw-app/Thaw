//
//  StatusIconStyleTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import WidgetsCore

/// The rules that make the icon show real readings: Wi-Fi bars, battery colours and its size.
@Suite("Status icon style")
struct StatusIconStyleTests {
    /// Three arcs of signal showed as two, because the raw strength didn't land on whole bars.
    @Test("Wi-Fi strength becomes the bars macOS shows", arguments: [
        (-45, 3), (-60, 3), (-61, 2), (-70, 2), (-71, 1), (-90, 1),
    ])
    func wifiBars(rssi: Int, bars: Int) {
        let strength = Double(rssi + 100) / 70
        #expect(StatusIconSignal.bars(strength: strength) == bars)
    }

    @Test("No signal shows no bars, and each bar count lands inside the symbol's band")
    func wifiVariableValue() {
        #expect(StatusIconSignal.bars(strength: 0) == 0)
        #expect(StatusIconSignal.bars(strength: .nan) == 0)
        #expect(StatusIconSignal.variableValue(bars: 0) == 0)
        #expect(StatusIconSignal.variableValue(bars: 1) > 0 && StatusIconSignal.variableValue(bars: 1) < 0.34)
        #expect(StatusIconSignal.variableValue(bars: 2) > 0.34 && StatusIconSignal.variableValue(bars: 2) < 0.67)
        #expect(StatusIconSignal.variableValue(bars: 3) > 0.67)
    }

    @Test("Charging is green, Low Power Mode yellow, a low battery red, and anything else plain")
    func batteryTint() {
        func tint(_ level: Double, charging: Bool = false, lowPower: Bool = false) -> StatusIconTint? {
            var samples = StatusIconSamples()
            samples.battery = level
            samples.isCharging = charging
            samples.isLowPowerMode = lowPower
            return StatusIconTint.battery(samples)
        }
        #expect(tint(0.1, charging: true) == .green)
        #expect(tint(0.5, lowPower: true) == .yellow)
        #expect(tint(0.1, lowPower: true) == .yellow, "Low Power Mode is what the user chose to see")
        #expect(tint(0.19) == .red)
        #expect(tint(0.2) == nil)
        #expect(tint(0.9) == nil)
    }

    @Test("A reading is tinted only when status colours are on, and volume turns blue on Bluetooth")
    func tintBySource() {
        var samples = StatusIconSamples()
        samples.battery = 0.1
        samples.audioOutput = StatusIconAudioOutput(name: "AirPods Pro", isBluetooth: true)
        var style = StatusIconStyle()
        #expect(style.tint(for: .battery, samples: samples) == .red)
        #expect(style.tint(for: .volume, samples: samples) == .blue)
        #expect(style.tint(for: .wifi, samples: samples) == nil)
        samples.audioOutput = StatusIconAudioOutput(name: "MacBook Pro Speakers", isBluetooth: false)
        #expect(style.tint(for: .volume, samples: samples) == nil)
        style.statusColors = false
        #expect(style.tint(for: .battery, samples: samples) == nil)
    }

    @Test("Large draws the arc and symbol bigger, and Regular is the indicator's own weight")
    func sizeAndThickness() {
        #expect(StatusIconStyle.Size.standard.fill < StatusIconStyle.Size.large.fill)
        #expect(StatusIconStyle.Size.large.fill == 1)
        #expect(StatusIconStyle.Thickness.regular.lineWidth == 0.057)
        #expect(StatusIconStyle.Thickness.thin.lineWidth < StatusIconStyle.Thickness.regular.lineWidth)
        #expect(StatusIconStyle.Thickness.regular.lineWidth < StatusIconStyle.Thickness.thick.lineWidth)
        #expect(!StatusIconStyle.Size.large.title.isEmpty && !StatusIconStyle.Thickness.thick.title.isEmpty)
    }

    @Test("The icon is a template only when nothing in it is coloured")
    func templateRendering() {
        var samples = StatusIconSamples()
        samples.battery = 0.9
        let composition = StatusIconComposition()
        #expect(!StatusIconStyle().hasColor(composition: composition, samples: samples))
        samples.battery = 0.1
        #expect(StatusIconStyle().hasColor(composition: composition, samples: samples))
        var hidden = composition
        hidden.outer = .none
        hidden.bottomSource = .wifi
        #expect(!StatusIconStyle().hasColor(composition: hidden, samples: samples), "battery isn't shown")
    }

    @Test("The saved names of readings and style options stay the same")
    func savedFormatIsPinned() throws {
        var samples = StatusIconSamples()
        samples.audioOutput = StatusIconAudioOutput(name: "AirPods", isBluetooth: true)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(samples)) as? [String: Any]
        #expect(Set(json?.keys ?? [:].keys) == [
            "network", "battery", "wifi", "volume", "cpu", "isCharging", "isLowPowerMode", "audioOutput",
        ])
        #expect(WidgetKeys.size == "StatusIconPrototype.size")
        #expect(WidgetKeys.thickness == "StatusIconPrototype.thickness")
        #expect(WidgetKeys.statusColors == "StatusIconPrototype.statusColors")
        #expect(StatusIconStyle.Size.allCases.map(\.rawValue) == ["standard", "large"])
        #expect(StatusIconStyle.Thickness.allCases.map(\.rawValue) == ["thin", "regular", "thick"])
    }

    @Test("Saved readings from before the new fields still load")
    func olderSavedSamplesDecode() throws {
        let old = Data(#"{"network":"wifi","battery":0.4,"wifi":0.6,"volume":0.3,"cpu":0.2}"#.utf8)
        let samples = try JSONDecoder().decode(StatusIconSamples.self, from: old)
        #expect(samples.battery == 0.4 && samples.volume == 0.3)
        #expect(!samples.isCharging && !samples.isLowPowerMode && samples.audioOutput == nil)

        var full = StatusIconSamples()
        full.isCharging = true
        full.audioOutput = StatusIconAudioOutput(name: "Beats Studio", isBluetooth: true)
        let roundTrip = try JSONDecoder().decode(StatusIconSamples.self, from: JSONEncoder().encode(full))
        #expect(roundTrip == full)
    }
}
