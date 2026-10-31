//
//  OnboardingStepIndicator.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Steps cannot be skipped, so dots report progress rather than acting as buttons.
/// VoiceOver reads the position as one sentence, not unlabeled circles.
public struct OnboardingStepIndicator: View {
    private let step: Int
    private let total: Int
    let label: LocalizedStringResource

    /// The label is the sentence VoiceOver reads, such as "Step 2 of 3".
    public init(step: Int, total: Int, label: LocalizedStringResource) {
        self.step = step
        self.total = total
        self.label = label
    }

    public var body: some View {
        HStack(spacing: ThawSpacing.base) {
            ForEach(1 ... max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }
}
