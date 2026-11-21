//
//  OnboardingView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Sized for the recovery screen's two columns of permission cards, the widest page the window shows.
enum ThawOnboardingWindowMetrics {
    static let width: CGFloat = 680
    static let height: CGFloat = 560
}

/// The host applies all decisions at completion; the flow never writes settings, so quitting leaves no partial changes.
nonisolated struct OnboardingOutcome: Equatable, Sendable {
    var automaticUpdates: Bool

    /// A first onboarding starts in Simple Mode; a replay, or an upgrade from an earlier tour, keeps the mode in use.
    static func simpleMode(current: Bool, hasSeenOnboarding: Bool) -> Bool {
        hasSeenOnboarding ? current : true
    }
}

/// Welcome, then access, then how to use Thaw. Nothing is written before the last page, so quitting
/// earlier leaves no settings behind.
struct ThawOnboardingView: View {
    enum Step {
        case welcome
        case access
        case done
    }

    @State private var step: Step

    private let skipsAccessStep: Bool
    private let onFinish: (OnboardingOutcome) -> Void

    /// - Parameters:
    ///   - skipsAccessStep: Goes from the welcome straight to the last page when access is already granted.
    ///   - startingStep: The screen the flow opens on, welcome for every real launch.
    ///   - onFinish: Called once at completion with the choices; the host applies them.
    init(
        skipsAccessStep: Bool,
        startingStep: Step = .welcome,
        onFinish: @escaping (OnboardingOutcome) -> Void
    ) {
        self.skipsAccessStep = skipsAccessStep
        _step = State(initialValue: startingStep)
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                OnboardingWelcomeView(onContinue: { step = skipsAccessStep ? .done : .access })
                    .transition(.opacity)
            case .access:
                ThawPermissionsView(mode: .onboarding) { step = .done }
                    .transition(.opacity)
            case .done:
                OnboardingDoneView(onFinish: onFinish)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingStepAnimation(value: step)
    }
}
