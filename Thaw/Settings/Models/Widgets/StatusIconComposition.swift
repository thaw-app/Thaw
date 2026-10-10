//
//  StatusIconComposition.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A three-slot recipe, independent of where readings come from or the icon is drawn.
/// The prototype persists one recipe and can publish it as a temporary status item.
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
        case none, wifi, bolt, moon, cpu

        var title: String {
            switch self {
            case .none: String(localized: "None")
            case .wifi: String(localized: "Network (automatic)")
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
            case .bolt: "bolt.fill"
            case .moon: "moon.fill"
            case .cpu: "cpu"
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
