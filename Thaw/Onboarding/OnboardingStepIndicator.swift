//
//  OnboardingStepIndicator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Steps cannot be skipped, so dots report progress rather than acting as buttons.
/// VoiceOver reads the position as one sentence, not unlabeled circles.
struct OnboardingStepIndicator: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: ThawSpacing.base) {
            ForEach(1 ... max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step) of \(total)"))
    }
}
