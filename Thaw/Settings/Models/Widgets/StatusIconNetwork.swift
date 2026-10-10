//
//  StatusIconNetwork.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Network

/// The default route, not merely an enabled Wi-Fi radio. A satisfied path
/// describes connectivity; it does not prove that the internet is reachable.
nonisolated enum StatusIconNetwork: String, Codable, CaseIterable, Sendable {
    case unknown, wifi, ethernet, cellular, other, disconnected

    init(status: NWPath.Status, usedInterfaces: [NWInterface.InterfaceType]) {
        guard status == .satisfied else {
            self = .disconnected
            return
        }
        if usedInterfaces.contains(.wiredEthernet) {
            self = .ethernet
        } else if usedInterfaces.contains(.wifi) {
            self = .wifi
        } else if usedInterfaces.contains(.cellular) {
            self = .cellular
        } else {
            self = .other
        }
    }

    var title: String {
        switch self {
        case .unknown: String(localized: "Checking connection")
        case .wifi: String(localized: "Wi-Fi")
        case .ethernet: String(localized: "Ethernet")
        case .cellular: String(localized: "Cellular")
        case .other: String(localized: "Other network connection")
        case .disconnected: String(localized: "Disconnected")
        }
    }

    /// Nil draws the custom Ethernet packet glyph instead of a stock symbol.
    var symbolName: String? {
        switch self {
        case .unknown: "questionmark"
        case .wifi: "wifi"
        case .ethernet: nil
        case .cellular: "antenna.radiowaves.left.and.right"
        case .other: "network"
        case .disconnected: "network.slash"
        }
    }
}

/// One snapshot drives the settings preview, published image, click menu, and
/// accessibility text, so changes to the recipe and to readings take the same path.
struct StatusIconPreviewState: Equatable {
    var composition: StatusIconComposition
    var samples: StatusIconSamples
    var isLive: Bool

    var title: String {
        isLive ? String(localized: "Thaw widget · Live readings") : String(localized: "Thaw widget · Sample readings")
    }

    var sources: [StatusIconComposition.Source] {
        StatusIconComposition.Source.allCases.filter { source in
            composition.activeSources.contains(source) || (source == .wifi && composition.center == .wifi && samples.network == .wifi)
        }
    }

    var details: [String] {
        guard !composition.isEmpty else { return [String(localized: "No indicators selected")] }
        var parts = [String]()
        if composition.center == .wifi {
            parts.append(String(localized: "Connection: \(samples.network.title)"))
        } else if composition.center != .none {
            parts.append(String(localized: "Symbol: \(composition.center.title)"))
        }
        for source in sources {
            let value = samples[source].formatted(.percent.precision(.fractionLength(0)))
            if isLive, source == .volume {
                parts.append(String(localized: "Volume: \(value) (manual)"))
            } else {
                parts.append(String(localized: "\(source.title): \(value)"))
            }
        }
        return parts
    }

    var accessibilityDescription: String {
        ([title] + details).joined(separator: ". ")
    }
}
