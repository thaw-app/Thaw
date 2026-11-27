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
