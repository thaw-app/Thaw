//  Adapted from Barometer (https://github.com/mackid1993/Barometer)
//  Copyright (Barometer) © 2026 mackid1993. Used with permission.
//  Licensed under the GNU GPLv3
//
//  WiFiSource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import CoreWLAN
import Foundation

/// Current Wi-Fi link details. Location-protected fields are optional.
public struct WiFiSnapshot: Equatable, Sendable {
    public let interfaceName: String
    public let isPowered: Bool
    public let ssid: String?
    public let bssid: String?
    public let rssi: Int?
    public let noise: Int?
    public let channel: Int?
    public let band: String?
    public let transmitRateMbps: Double?
    public let security: String?
}

/// Reads the active CoreWLAN interface without requesting Location permission itself.
public struct WiFiSource: Sendable {
    /// Whether this Mac exposes a Wi-Fi interface.
    public var isAvailable: Bool {
        CWWiFiClient.shared().interface() != nil
    }

    /// Creates a Wi-Fi source.
    public init() {}

    /// Reads the selected or default Wi-Fi interface.
    public func read(interfaceName: String? = nil) -> WiFiSnapshot? {
        let client = CWWiFiClient.shared()
        guard let interface = interfaceName.flatMap(client.interface(withName:)) ?? client.interface(),
              let name = interface.interfaceName
        else {
            return nil
        }
        let channel = interface.wlanChannel()
        let rssi = interface.rssiValue()
        let noise = interface.noiseMeasurement()
        let transmitRate = interface.transmitRate()
        let security = interface.security()
        return WiFiSnapshot(
            interfaceName: name,
            isPowered: interface.powerOn(),
            ssid: interface.ssid(),
            bssid: interface.bssid(),
            rssi: rssi == 0 ? nil : rssi,
            noise: noise == 0 ? nil : noise,
            channel: channel.map { Int($0.channelNumber) },
            band: channel.flatMap { Self.bandName(rawValue: $0.channelBand.rawValue) },
            transmitRateMbps: transmitRate > 0 ? transmitRate : nil,
            security: Self.securityName(rawValue: security.rawValue)
        )
    }

    private static func bandName(rawValue: Int) -> String? {
        switch rawValue {
        case 1: "2.4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: nil
        }
    }

    private static func securityName(rawValue: Int) -> String? {
        switch rawValue {
        case 0: "Open"
        case 1: "WEP"
        case 2: "WPA Personal"
        case 3: "WPA/WPA2 Personal"
        case 4: "WPA2 Personal"
        case 5: "Personal"
        case 6: "Dynamic WEP"
        case 7: "WPA Enterprise"
        case 8: "WPA/WPA2 Enterprise"
        case 9: "WPA2 Enterprise"
        case 10: "Enterprise"
        case 11: "WPA3 Personal"
        case 12: "WPA3 Enterprise"
        case 13: "WPA3/WPA2 Personal"
        case 14: "OWE"
        case 15: "OWE Transition"
        default: nil
        }
    }
}
