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

/// One snapshot drives the builder's preview, the menu bar image, the click
/// menu and the accessibility text, so changes to the recipe and to readings take the same path.
struct StatusIconPreviewState: Equatable {
    var composition: StatusIconComposition
    var samples: StatusIconSamples
    var isLive: Bool
    var style = StatusIconStyle()

    var title: String {
        isLive ? String(localized: "Thaw widget · Live readings") : String(localized: "Thaw widget · Sample readings")
    }

    var sources: [StatusIconComposition.Source] {
        StatusIconComposition.Source.allCases.filter { source in
            composition.activeSources.contains(source)
                || (source == .wifi && composition.center.showsNetwork(for: samples) && samples.network == .wifi)
        }
    }

    var details: [String] {
        guard !composition.isEmpty else { return [String(localized: "No indicators selected")] }
        var parts = [String]()
        if composition.center.showsNetwork(for: samples) {
            parts.append(String(localized: "Connection: \(samples.network.title)"))
        } else if composition.center == .bluetooth, let output = samples.audioOutput {
            parts.append(String(localized: "Playing through \(output.name)"))
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

    /// What the icon draws and says, to the precision either shows. A reading no indicator uses, or
    /// a change of less than a percent, leaves it equal, so that sample need not redraw the icon.
    var displayed: StatusIconDisplayedContent {
        StatusIconDisplayedContent(
            composition: composition,
            style: style,
            title: title,
            details: details,
            centerSymbol: composition.center.symbolName(for: samples),
            tints: composition.activeSources.map { style.tint(for: $0, samples: samples) }
        )
    }
}

extension StatusIconPreviewState {
    /// What the image draws, to the precision it shows: whole percents around the outside, lit
    /// segments below and signal bars in the centre. A reading can change its text and not its picture.
    var drawn: StatusIconDrawnContent {
        let showsWifi = composition.center.showsNetwork(for: samples) && samples.network == .wifi
        return StatusIconDrawnContent(
            composition: composition,
            style: style,
            centerSymbol: composition.center.symbolName(for: samples),
            tints: composition.activeSources.map { style.tint(for: $0, samples: samples) },
            outerPercent: composition.outer == .none ? nil : Int((samples[composition.outerSource] * 100).rounded()),
            signalBars: showsWifi ? StatusIconSignal.bars(strength: samples[.wifi]) : nil,
            litSegments: composition.bottom == .none ? nil : samples.litSegments(for: composition.bottomSource)
        )
    }
}

/// The inputs of the menu bar image.
struct StatusIconDrawnContent: Equatable {
    var composition: StatusIconComposition
    var style: StatusIconStyle
    var centerSymbol: String?
    var tints: [StatusIconTint?]
    var outerPercent: Int?
    var signalBars: Int?
    var litSegments: Int?
}

/// The parts of a preview state that reach the screen or VoiceOver.
struct StatusIconDisplayedContent: Equatable {
    var composition: StatusIconComposition
    var style: StatusIconStyle
    var title: String
    var details: [String]
    var centerSymbol: String?
    var tints: [StatusIconTint?]
}
