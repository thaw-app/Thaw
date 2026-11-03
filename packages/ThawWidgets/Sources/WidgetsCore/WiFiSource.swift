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

/// Reads the Wi-Fi signal strength from CoreWLAN without asking for
/// Location permission, which only the network name would need.
struct WiFiSource: Sendable {
    /// The signal strength of the default Wi-Fi interface in dBm, or nil
    /// without Wi-Fi or a link.
    func rssi() -> Int? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let rssi = interface.rssiValue()
        return rssi == 0 ? nil : rssi
    }
}
