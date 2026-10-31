//
//  ThawListHeading.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Small uppercase heading over a group of rows; callers set the spacing.
public struct ThawListHeading: View {
    private let title: Text

    public init(_ title: Text) {
        self.title = title
    }

    public init(_ title: LocalizedStringResource) {
        self.title = Text(title)
    }

    public var body: some View {
        title
            .font(ThawType.sublabel.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}
