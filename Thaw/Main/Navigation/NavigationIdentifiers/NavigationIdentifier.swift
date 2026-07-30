//
//  NavigationIdentifier.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A type that represents an identifier for a navigation destination.
protocol NavigationIdentifier: CaseIterable, Hashable, Identifiable, RawRepresentable {
    /// An icon for the identifier's navigation destination.
    var iconResource: IconResource { get }

    /// A localized description for the identifier's navigation destination.
    var localized: LocalizedStringKey { get }
}

extension NavigationIdentifier where ID == Int {
    var id: Int {
        hashValue
    }
}

extension NavigationIdentifier where RawValue == String {
    var localized: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
}
