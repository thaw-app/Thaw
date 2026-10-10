//
//  OnboardingView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Shared dimensions leave room for the bento grid, which needs more space than welcome or access.
enum ThawOnboardingWindowMetrics {
    static let width: CGFloat = 760
    static let height: CGFloat = 580
}

/// The host applies all decisions at completion; the flow never writes settings, so quitting leaves no partial changes.
nonisolated struct OnboardingOutcome: Equatable, Sendable {
    var simpleMode: Bool
    var automaticUpdates: Bool
}

/// Ask for access after explaining its benefits; earlier screens need no grants and cannot fail for missing permissions.
/// Hold choices through access and let the host apply them together, so quitting leaves no partial settings.
struct ThawOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step {
        case welcome
        case bento
        case access
    }

    @State private var step = Step.welcome
    /// Hold bento choices until access completes to avoid abandoned, partially applied settings.
    @State private var pendingOutcome: OnboardingOutcome?
    @State private var pendingPane: SettingsNavigationIdentifier?

    private let skipsAccessStep: Bool
    private let onFinish: (OnboardingOutcome, SettingsNavigationIdentifier?) -> Void

    /// - Parameters:
    ///   - skipsAccessStep: Ends at the bento when permissions are already granted, avoiding a redundant request.
    ///   - onFinish: Called once at completion with choices and an optional Settings destination; the host applies them.
    init(skipsAccessStep: Bool, onFinish: @escaping (OnboardingOutcome, SettingsNavigationIdentifier?) -> Void) {
        self.skipsAccessStep = skipsAccessStep
        self.onFinish = onFinish
    }

    /// How many numbered steps the flow has: the bento and access, less the
    /// access step when it is skipped.
    private var indicatorTotal: Int {
        skipsAccessStep ? 1 : 2
    }

    /// Hide numbering on welcome and when bento is the only step, since "1 of 1" conveys no progress.
    private var indicatorStep: Int? {
        switch step {
        case .welcome: nil
        case .bento: skipsAccessStep ? nil : 1
        case .access: 2
        }
    }

    /// What to hand the host if the access step somehow finishes without
    /// the bento having run: the same defaults the bento starts with.
    private var defaultOutcome: OnboardingOutcome {
        OnboardingOutcome(simpleMode: true, automaticUpdates: true)
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView(onContinue: { step = .bento })
                    .transition(.opacity)
            case .bento:
                OnboardingBentoView(
                    finishesFlow: skipsAccessStep,
                    onFinish: { outcome, pane in
                        guard !skipsAccessStep else {
                            onFinish(outcome, pane)
                            return
                        }
                        pendingOutcome = outcome
                        pendingPane = pane
                        step = .access
                    }
                )
                .transition(.opacity)
            case .access:
                ThawPermissionsView(mode: .onboarding, finishesFlow: true) {
                    onFinish(pendingOutcome ?? defaultOutcome, pendingPane)
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let indicatorStep {
                OnboardingStepIndicator(step: indicatorStep, total: indicatorTotal)
                    .padding(.top, ThawSpacing.inset)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .thawAnimation(ThawMotion.settle, value: step)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}
