//
//  Defaults+Codable.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

nonisolated extension Defaults {
    /// The value stored as JSON data under key, or nil when no data is stored there.
    ///
    /// - Throws: The decoding error when the stored data does not decode as Value.
    static func decoded<Value: Decodable>(_: Value.Type, forKey key: Key) throws -> Value? {
        guard let data = data(forKey: key) else { return nil }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// Stores value as JSON data under key.
    ///
    /// - Throws: The encoding error, in which case the stored value is left as it was.
    static func setEncoded(_ value: some Encodable, forKey key: Key) throws {
        try set(JSONEncoder().encode(value), forKey: key)
    }
}
