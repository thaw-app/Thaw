//
//  OnboardingPageIndicator.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct OnboardingPageIndicator: View {
    let totalPages: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: index == currentPage ? 18 : 6, height: 6)
                    .animation(.snappy, value: currentPage)
            }
        }
    }
}
