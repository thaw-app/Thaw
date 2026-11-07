//
//  StatusIconStyle.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation

/// How the icon is drawn: its size, its ring's thickness and whether readings carry status colours.
struct StatusIconStyle: Equatable {
    var size: Size = .standard
    var thickness: Thickness = .regular
    var statusColors = true

    /// The raw values are saved, so they never change.
    enum Size: String, CaseIterable {
        case standard, large

        var title: String {
            switch self {
            case .standard: String(localized: "Standard")
            case .large: String(localized: "Large")
            }
        }

        /// Large grows the ring and the centre symbol inside the same square, so it fits any menu bar.
        var scale: CGFloat {
            switch self {
            case .standard: 1
            case .large: 1.12
            }
        }
    }

    /// The raw values are saved, so they never change.
    enum Thickness: String, CaseIterable {
        case thin, regular, thick

        var title: String {
            switch self {
            case .thin: String(localized: "Thin")
            case .regular: String(localized: "Regular")
            case .thick: String(localized: "Thick")
            }
        }

        /// The ring's stroke as a fraction of the icon's side.
        var lineWidth: CGFloat {
            switch self {
            case .thin: 0.05
            case .regular: 0.065
            case .thick: 0.085
            }
        }
    }

    /// The ring's radius as a fraction of the icon's side.
    var arcRadius: CGFloat {
        0.35 * size.scale
    }

    var lineWidth: CGFloat {
        thickness.lineWidth
    }

    /// The colour a reading is drawn in, or nil for the menu bar's own ink.
    func tint(for source: StatusIconComposition.Source, samples: StatusIconSamples) -> StatusIconTint? {
        guard statusColors else { return nil }
        switch source {
        case .battery: return StatusIconTint.battery(samples)
        case .volume: return samples.audioOutput?.isBluetooth == true ? .blue : nil
        case .wifi, .cpu: return nil
        }
    }

    /// Whether any reading the composition shows is coloured; a template image can't carry colour.
    func hasColor(composition: StatusIconComposition, samples: StatusIconSamples) -> Bool {
        composition.activeSources.contains { tint(for: $0, samples: samples) != nil }
    }
}

/// A status colour, as on an iPhone's battery: charging, Low Power Mode, low, and Bluetooth audio.
enum StatusIconTint: Equatable {
    case green, yellow, red, blue

    /// Charging wins over Low Power Mode, and both win over a low charge.
    static func battery(_ samples: StatusIconSamples) -> StatusIconTint? {
        if samples.isCharging {
            return .green
        }
        if samples.isLowPowerMode {
            return .yellow
        }
        return samples[.battery] < 0.2 ? .red : nil
    }
}

/// Wi-Fi bars as macOS draws them, from the 0–1 strength the sampler stores, (RSSI + 100) / 70.
enum StatusIconSignal {
    static func bars(strength: Double) -> Int {
        guard strength.isFinite, strength > 0 else { return 0 }
        let rssi = strength * 70 - 100
        if rssi >= -60 {
            return 3
        }
        return rssi >= -70 ? 2 : 1
    }

    /// The wifi symbol lights one arc above 0, two above about 0.34 and three above about 0.67.
    static func variableValue(bars: Int) -> Double {
        switch bars {
        case ...0: 0
        case 1: 0.2
        case 2: 0.55
        default: 1
        }
    }
}

/// The current audio output, so a Bluetooth device can take the centre and tint the volume.
struct StatusIconAudioOutput: Codable, Equatable, Sendable {
    var name: String
    var isBluetooth: Bool

    /// The device's symbol, chosen from its name since no public API names one; headphones otherwise.
    var symbolName: String {
        let name = name.lowercased()
        if name.contains("airpods max") {
            return "airpods.max"
        }
        if name.contains("airpods pro") {
            return "airpods.pro"
        }
        if name.contains("airpods") {
            return "airpods"
        }
        if name.contains("beats") {
            return "beats.headphones"
        }
        if name.contains("homepod") {
            return "homepod"
        }
        if name.contains("speaker") {
            return "hifispeaker"
        }
        return "headphones"
    }
}
