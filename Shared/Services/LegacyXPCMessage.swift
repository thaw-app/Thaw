//
//  LegacyXPCMessage.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import XPC

/// Codable messages over the C XPC API, which the helpers use before macOS 26.
/// Each value travels as a binary property list under one key.
nonisolated enum LegacyXPCMessage {
    static let payloadKey = "payload"

    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(_: Value.Type, from data: Data) throws -> Value {
        try PropertyListDecoder().decode(Value.self, from: data)
    }

    /// Writes the encoded value into dictionary.
    static func setPayload(_ value: some Encodable, in dictionary: xpc_object_t) throws {
        let data = try encode(value)
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            xpc_dictionary_set_data(dictionary, payloadKey, baseAddress, buffer.count)
        }
    }

    /// The payload in dictionary, or nil when it carries none.
    static func payload(in dictionary: xpc_object_t) -> Data? {
        guard xpc_get_type(dictionary) == XPC_TYPE_DICTIONARY else { return nil }
        var length = 0
        guard let bytes = xpc_dictionary_get_data(dictionary, payloadKey, &length), length > 0 else {
            return nil
        }
        return Data(bytes: bytes, count: length)
    }

    /// A code requirement that admits only processes signed by teamIdentifier,
    /// or nil when the identifier isn't a ten-character team ID.
    static func sameTeamRequirement(teamIdentifier: String) -> String? {
        let isTeamID = teamIdentifier.count == 10
            && teamIdentifier.unicodeScalars.allSatisfy { scalar in
                ("A" ... "Z").contains(scalar) || ("0" ... "9").contains(scalar)
            }
        guard isTeamID else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    /// Restricts connection's peer to this process's team, when it has one.
    /// False means the requirement didn't apply and the connection must not be used.
    static func applySameTeamRequirement(to connection: xpc_connection_t, teamIdentifier: String?) -> Bool {
        guard let teamIdentifier else { return true }
        guard let requirement = sameTeamRequirement(teamIdentifier: teamIdentifier) else { return false }
        return xpc_connection_set_peer_code_signing_requirement(connection, requirement) == 0
    }

    /// Drops a connection that was never activated. libxpc traps when one is
    /// released without being activated first.
    static func discard(_ connection: xpc_connection_t) {
        xpc_connection_set_event_handler(connection) { _ in
            // A discarded connection has nothing left to handle.
        }
        xpc_connection_activate(connection)
        xpc_connection_cancel(connection)
    }
}

/// XPC objects are safe to use from any thread; the C types just aren't marked Sendable.
nonisolated struct SendableXPCObject: @unchecked Sendable {
    let object: xpc_object_t
}
