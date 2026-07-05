//
//  ThawOnboardingView.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Shared window dimensions for onboarding and permissions flows.
enum ThawOnboardingWindowMetrics {
    static let width: CGFloat = 608
    static let height: CGFloat = 480
}

/// Full first-launch experience: feature tour, then separate permissions
/// screen, then optional completion confirmation.
struct ThawOnboardingView: View {
    private enum Step {
        case tour
        case permissions
        case done
    }

    @State private var step = Step.tour

    private let showsCompletionScreen: Bool
    private let onComplete: () -> Void

    /// Creates the reusable onboarding flow.
    /// - Parameters:
    ///   - showsCompletionScreen: When `true`, the package shows a final
    ///     confirmation screen after permissions. Set this to `false` when the
    ///     host app dismisses onboarding in `onComplete`.
    ///   - onComplete: Called once the user finishes the permissions step.
    init(
        showsCompletionScreen: Bool = true,
        onComplete: @escaping () -> Void
    ) {
        self.showsCompletionScreen = showsCompletionScreen
        self.onComplete = onComplete
    }

    var body: some View {
        Group {
            switch step {
            case .tour:
                ThawOnboardingTour(onFinish: { step = .permissions })
                    .transition(.opacity)
            case .permissions:
                ThawPermissionsView(onContinue: complete)
                    .transition(.opacity)
            case .done:
                ThawOnboardingDoneView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.35), value: step)
    }

    private func complete() {
        if showsCompletionScreen {
            step = .done
        }

        onComplete()
    }
}

private struct ThawOnboardingDoneView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.green)

            Text("You're All Set")
                .font(.title.bold())

            Text("Thaw is ready to manage your menu bar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
    }
}
