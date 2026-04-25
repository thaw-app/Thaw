//
//  BetaBadge.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A view that displays a badge indicating a beta feature.
struct BetaBadge: View {
    private var backgroundShape: some Shape {
        Capsule()
    }

    var body: some View {
        Text("BETA")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                backgroundShape
                    .fill(.quaternary)
            }
            .foregroundStyle(.green)
    }
}
