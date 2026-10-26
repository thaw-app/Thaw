//
//  StoredProfileID.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

/// A profile ID kept across launches as a UUID string under one defaults key.
nonisolated struct StoredProfileID {
    let key: String
    let defaults: UserDefaults

    var id: UUID? {
        get { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.uuidString, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
