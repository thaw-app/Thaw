//
//  StatusIconComposition.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A three-slot recipe, independent of where readings come from or where the
/// icon is drawn. The module saves one recipe and shows it as its status item.
struct StatusIconComposition: Equatable {
    var outer: Outer = .arc
    var outerSource: Source = .battery
    var center: Center = .wifi
    var bottom: Bottom = .dots
    var bottomSource: Source = .wifi

    var isEmpty: Bool {
        outer == .none && center == .none && bottom == .none
    }

    /// Only readings used by visible indicators, in a stable order without duplicates.
    var activeSources: [Source] {
        Source.allCases.filter { source in
            (outer != .none && outerSource == source) || (bottom != .none && bottomSource == source)
        }
    }

    enum Outer: String, CaseIterable {
        case none, arc, ring

        var title: String {
            switch self {
            case .none: String(localized: "None")
            case .arc: String(localized: "Arc")
            case .ring: String(localized: "Ring")
            }
        }
    }

    enum Center: String, CaseIterable {
        case none, wifi, bluetooth, bolt, moon, cpu

        var title: String {
            switch self {
            case .none: String(localized: "None")
            case .wifi: String(localized: "Network (automatic)")
            case .bluetooth: String(localized: "Bluetooth audio, else network")
            case .bolt: String(localized: "Lightning bolt")
            case .moon: String(localized: "Moon")
            case .cpu: String(localized: "CPU")
            }
        }

        /// Preserve the persisted wifi case name even though its symbol follows the network route.
        func symbolName(for samples: StatusIconSamples) -> String? {
            switch self {
            case .none: nil
            case .wifi: samples.network.symbolName
            case .bluetooth: showsNetwork(for: samples) ? samples.network.symbolName : samples.audioOutput?.symbolName
            case .bolt: "bolt.fill"
            case .moon: "moon.fill"
            case .cpu: "cpu"
            }
        }

        /// Whether the centre draws the network: always for network, and for Bluetooth audio when nothing plays through Bluetooth.
        func showsNetwork(for samples: StatusIconSamples) -> Bool {
            switch self {
            case .wifi: true
            case .bluetooth: samples.audioOutput?.isBluetooth != true
            case .none, .bolt, .moon, .cpu: false
            }
        }
    }

    enum Bottom: String, CaseIterable {
        case none, dots, bars

        var title: String {
            switch self {
            case .none: String(localized: "None")
            case .dots: String(localized: "Dots")
            case .bars: String(localized: "Bars")
            }
        }
    }

    enum Source: String, CaseIterable {
        case battery, wifi, volume, cpu

        var title: String {
            switch self {
            case .battery: String(localized: "Battery level")
            case .wifi: String(localized: "Wi-Fi strength")
            case .volume: String(localized: "Volume")
            case .cpu: String(localized: "CPU usage")
            }
        }
    }
}

/// A value snapshot supplied by either the manual controls or live sampler.
struct StatusIconSamples: Codable, Equatable {
    var network: StatusIconNetwork = .wifi
    var battery = 0.75
    var wifi = 1.0
    var volume = 0.5
    var cpu = 0.25
    var isCharging = false
    var isLowPowerMode = false
    var audioOutput: StatusIconAudioOutput?
    /// False on a Mac with no battery, where the charge reads 0 for want of a source.
    /// Without it that 0 would look like an empty battery and force a fixed bitmap.
    var hasBattery = true

    /// The saved key names; a test pins them, since renaming one would drop saved readings.
    enum CodingKeys: String, CodingKey {
        case network, battery, wifi, volume, cpu, isCharging, isLowPowerMode, audioOutput, hasBattery
    }

    subscript(source: StatusIconComposition.Source) -> Double {
        get {
            let value = switch source {
            case .battery: battery
            case .wifi: wifi
            case .volume: volume
            case .cpu: cpu
            }
            return value.isFinite ? value.clamped(to: 0 ... 1) : 0
        }
        set {
            switch source {
            case .battery: battery = newValue
            case .wifi: wifi = newValue
            case .volume: volume = newValue
            case .cpu: cpu = newValue
            }
        }
    }

    /// Round up so a nonzero reading always lights at least one segment.
    func litSegments(for source: StatusIconComposition.Source) -> Int {
        Int((self[source] * 4).rounded(.up))
    }
}

extension StatusIconSamples {
    /// Readings saved before a field existed decode with its default.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decodeIfPresent(StatusIconNetwork.self, forKey: .network) ?? network
        battery = try container.decodeIfPresent(Double.self, forKey: .battery) ?? battery
        wifi = try container.decodeIfPresent(Double.self, forKey: .wifi) ?? wifi
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? volume
        cpu = try container.decodeIfPresent(Double.self, forKey: .cpu) ?? cpu
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
        isLowPowerMode = try container.decodeIfPresent(Bool.self, forKey: .isLowPowerMode) ?? false
        audioOutput = try container.decodeIfPresent(StatusIconAudioOutput.self, forKey: .audioOutput)
        hasBattery = try container.decodeIfPresent(Bool.self, forKey: .hasBattery) ?? hasBattery
    }
}
