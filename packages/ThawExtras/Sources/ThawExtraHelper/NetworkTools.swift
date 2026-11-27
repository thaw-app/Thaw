//
//  NetworkTools.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import SystemConfiguration

/// The interface's IPv4 address and the router, from the system's network
/// state. Reading them needs no permission.
struct NetworkAddresses: Equatable {
    var address: String?
    var router: String?

    static func current(interface: String?) -> NetworkAddresses {
        guard let interface, let store = SCDynamicStoreCreate(nil, "ThawExtraHelper" as CFString, nil, nil) else {
            return NetworkAddresses()
        }
        let interfaceState = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(interface)/IPv4" as CFString) as? [String: Any]
        let globalState = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        return NetworkAddresses(interfaceState: interfaceState, globalState: globalState, interface: interface)
    }

    /// The router counts only while this interface carries the default route.
    init(interfaceState: [String: Any]?, globalState: [String: Any]?, interface: String) {
        address = (interfaceState?["Addresses"] as? [String])?.first
        router = globalState?["PrimaryInterface"] as? String == interface ? globalState?["Router"] as? String : nil
    }

    init(address: String? = nil, router: String? = nil) {
        self.address = address
        self.router = router
    }
}

/// Runs macOS's own networkQuality tool, which takes about fifteen seconds.
enum ConnectionSpeedTest {
    enum State: Equatable {
        case idle
        case running
        case finished(Result)
        case failed
    }

    struct Result: Equatable {
        /// Megabits per second.
        var download: Int
        var upload: Int

        var summary: String {
            String(localized: "\(download) Mbps down, \(upload) Mbps up")
        }
    }

    /// A stalled test would otherwise leave the menu saying it is still running.
    static let timeout = Duration.seconds(90)

    static func run() async -> Result? {
        let output = await CommandOutput.output(of: URL(filePath: "/usr/bin/networkQuality"), arguments: ["-c"], timeout: timeout)
        return parse(Data(output.utf8))
    }

    /// networkQuality -c prints JSON with throughput in bits per second.
    static func parse(_ data: Data) -> Result? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let down = (json["dl_throughput"] as? NSNumber)?.doubleValue,
              let up = (json["ul_throughput"] as? NSNumber)?.doubleValue
        else { return nil }
        return Result(download: Int((down / 1_000_000).rounded()), upload: Int((up / 1_000_000).rounded()))
    }
}
