//
//  OnboardingTour.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Observation
import SwiftUI

/// The first-launch onboarding tour: the welcome scene is static — it plays
/// its own demo but never auto-advances, waiting for an explicit "Continue"
/// tap. From there, the remaining feature slides (Management, Appearance,
/// Hotkeys, Profiles) loop continuously — each running its own demo and
/// advancing on its own, wrapping back to Management after Profiles — until
/// the user taps "Get Started" to move on to permissions. The single
/// anchored button (same position and size on every slide) reads "Continue"
/// on the welcome slide and "Get Started" everywhere in the loop.
struct ThawOnboardingTour: View {
    var onFinish: () -> Void

    @State private var currentSlide = 0
    /// Guards against a single tap being registered twice in quick succession
    /// (trackpad chatter, or a stray double event) — without this, a double
    /// tap silently skips a slide.
    @State private var isNavigating = false
    // Invalidates any pending auto-advance timer when the slide changes for
    // any reason (auto or manual), so a stale timer from a skipped slide
    // can't also fire later.
    @State private var navigationTask: Task<Void, Never>?
    @State private var autoAdvanceTask: Task<Void, Never>?

    @State private var welcomeModel = ThawWelcomeModel()
    @State private var managementModel = ThawManagementMockupModel()
    @State private var appearanceModel = ThawAppearanceMockupModel()
    @State private var hotkeysModel = ThawHotkeysMockupModel()
    @State private var profilesModel = ThawProfilesMockupModel()

    private let slides = ThawTourSlide.allCases
    /// The welcome slide (index 0) plays once and is never looped back to;
    /// the loop lives entirely within the remaining slides.
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
            ForEach(slides.dropFirst()) { slide in
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
                .accessibilityLabel(String(localized: "Page \(index + 1) of \(slides.count)"))
            }
        }
        .opacity(isWelcome ? 0 : 1)
        .allowsHitTesting(!isWelcome)
        .padding(.top, 2)
    }

    // MARK: Bottom area — anchored the same way on every slide

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
                if isWelcome { advanceOrLoop() } else { onFinish() }
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

    /// Claims a short exclusive window for one navigation action. Returns
    /// `false` if another action already claimed it recently, so a
    /// duplicated tap event is dropped instead of firing twice.
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
        // Welcome is static — only the looping slides auto-advance.
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
