//
//  OnboardingTour.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation
import SwiftUI

/// The first-launch onboarding tour. Welcome waits for "Continue"; the
/// feature slides then loop on their own until the user taps "Get Started".
struct ThawOnboardingTour: View {
    var onFinish: () -> Void

    @State private var currentSlide = 0
    /// Drops a tap registered twice in quick succession, which would skip a slide.
    @State private var isNavigating = false
    // Cancelled on every slide change so a stale timer can't fire later.
    @State private var navigationTask: Task<Void, Never>?
    @State private var autoAdvanceTask: Task<Void, Never>?

    @State private var welcomeModel = ThawWelcomeModel()
    @State private var managementModel = ThawManagementMockupModel()
    @State private var appearanceModel = ThawAppearanceMockupModel()
    @State private var hotkeysModel = ThawHotkeysMockupModel()
    @State private var profilesModel = ThawProfilesMockupModel()

    private let slides = ThawTourSlide.allCases
    /// The welcome slide (index 0) is never looped back to.
    private let firstLoopingIndex = 1

    private var isWelcome: Bool {
        currentSlide == 0
    }

    private var current: ThawTourSlide {
        slides[currentSlide]
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                Spacer().frame(height: 19)

                Group {
                    switch current {
                    case .welcome:
                        ThawWelcomeMockup(model: welcomeModel)
                    case .menuBarManagement:
                        ManagementSlideMockup(model: managementModel, onInteraction: resetAutoAdvanceTimer)
                    case .menuBarAppearance:
                        AppearanceSlideMockup(model: appearanceModel, onInteraction: resetAutoAdvanceTimer)
                    case .hotkeysAutomation:
                        HotkeysSlideMockup(model: hotkeysModel, onInteraction: resetAutoAdvanceTimer)
                    case .profiles:
                        ProfilesSlideMockup(model: profilesModel, onInteraction: resetAutoAdvanceTimer)
                    }
                }
                .frame(height: 272)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
                .id(currentSlide)

                pageDots
                bottomArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectBackground())
        }
        .onAppear { restartCurrentSlide() }
        .onChange(of: currentSlide) { _, _ in restartCurrentSlide() }
        .onDisappear {
            navigationTask?.cancel()
            autoAdvanceTask?.cancel()
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Array(slides.dropFirst().enumerated()), id: \.element) { position, slide in
                let index = slide.rawValue
                Button {
                    guard beginNavigation() else { return }
                    withAnimation(.snappy) {
                        currentSlide = index
                    }
                } label: {
                    Circle()
                        .fill(currentSlide == index ? Color.primary : Color.secondary.opacity(0.28))
                        .frame(width: currentSlide == index ? 8 : 6, height: currentSlide == index ? 8 : 6)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // VoiceOver counts only the visible dots: the welcome slide
                // has no dot, so the loop's first slide is "Page 1".
                .accessibilityLabel(String(localized: "Page \(position + 1) of \(slides.count - 1)"))
            }
        }
        .opacity(isWelcome ? 0 : 1)
        .allowsHitTesting(!isWelcome)
        .accessibilityHidden(isWelcome)
        .padding(.top, 2)
    }

    // MARK: Bottom area, anchored the same way on every slide

    private var bottomArea: some View {
        VStack(spacing: 14) {
            VStack(spacing: 7) {
                Text(current.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(current.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }
            .id("slide-copy-\(currentSlide)")
            .transition(.opacity)
            .frame(minHeight: 61)

            Button {
                guard beginNavigation() else { return }
                if isWelcome {
                    advanceOrLoop()
                } else {
                    onFinish()
                }
            } label: {
                Text(isWelcome ? "Continue" : "Get Started")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 140, height: 34)
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .animation(.snappy, value: currentSlide)
    }

    // MARK: Helpers

    /// Returns `false` if another navigation claimed the window recently.
    private func beginNavigation() -> Bool {
        guard !isNavigating else { return false }
        isNavigating = true
        navigationTask?.cancel()
        navigationTask = Task {
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            isNavigating = false
        }
        return true
    }

    private func restartCurrentSlide() {
        switch current {
        case .welcome: welcomeModel.restart()
        case .menuBarManagement: managementModel.restart()
        case .menuBarAppearance: appearanceModel.restart()
        case .hotkeysAutomation: hotkeysModel.restart()
        case .profiles: profilesModel.restart()
        }
        scheduleAutoAdvance()
    }

    private func resetAutoAdvanceTimer() {
        scheduleAutoAdvance()
    }

    private func scheduleAutoAdvance() {
        autoAdvanceTask?.cancel()
        // Only the looping slides auto-advance.
        guard !isWelcome else { return }
        let delay = current.autoAdvanceDelay
        guard delay > 0 else { return }

        autoAdvanceTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            advanceOrLoop()
        }
    }

    /// Steps to the next slide, wrapping back to the first looping slide
    /// (not the welcome slide) once the last one finishes.
    private func advanceOrLoop() {
        withAnimation(.snappy) {
            if currentSlide == slides.count - 1 {
                currentSlide = firstLoopingIndex
            } else {
                currentSlide += 1
            }
        }
    }
}
