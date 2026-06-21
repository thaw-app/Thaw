//
//  OnboardingSheet.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - MacBook Bezel Frame

/// Frames `content` inside a stylized MacBook screen — bezel, notch, and lid
/// edge — and optionally zooms into a corner of it via ``OnboardingZoomSpec``.
struct MacBookBezelView<Content: View>: View {
    let content: Content
    /// Whether the screen should be zoomed into ``corner`` at ``scale``.
    var zoomed: Bool
    /// How far the screen zooms in when ``zoomed`` is `true`.
    var scale: CGFloat
    /// The unit point (within the zoomed content) the camera pushes into.
    var corner: UnitPoint

    @Environment(\.displayScale) private var displayScale

    init(
        zoomed: Bool = false,
        scale: CGFloat = 1,
        corner: UnitPoint = .center,
        @ViewBuilder content: () -> Content
    ) {
        self.zoomed = zoomed
        self.scale = scale
        self.corner = corner
        self.content = content()
    }

    private let screenRatio: CGFloat = 1.547
    private let macbookTint = Color(red: 0.79, green: 0.75, blue: 0.78)

    private let bezelCornerRadius: CGFloat = 16

    private func concentricShape(reducingRadiusBy delta: CGFloat) -> UnevenRoundedRectangle {
        let radius = max(bezelCornerRadius - delta, 0)
        return UnevenRoundedRectangle(
            topLeadingRadius: radius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: radius,
            style: .continuous
        )
    }

    private var bezelShape: UnevenRoundedRectangle {
        concentricShape(reducingRadiusBy: 0)
    }

    private func bottomOnlyCornerRadiusShape(_ radius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var bottomShape: UnevenRoundedRectangle {
        bottomOnlyCornerRadiusShape(9)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .clipShape(concentricShape(reducingRadiusBy: 2))
                .padding(2)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(concentricShape(reducingRadiusBy: 9))
                .padding(9)

            bezelShape
                .stroke(macbookTint, lineWidth: 4)

            bottomOnlyCornerRadiusShape(4)
                .fill(.black)
                .frame(width: 65, height: 10)
                .offset(y: 4.5)

            // The keyboard-side lid edge: the overlay is applied to the
            // 10-point bar before it expands to fill, then the assembled base
            // is pinned to the bottom.
            bottomShape
                .fill(macbookTint)
                .frame(height: 10)
                .overlay(alignment: .top) {
                    bottomShape
                        .fill(.black.opacity(0.3))
                        .frame(width: 45, height: 4)
                        .offset(y: -2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, -35)
                .offset(y: 9)
        }
        .environment(\.displayScale, displayScale * (zoomed ? scale : 1))
        .drawingGroup(opaque: false)
        .aspectRatio(screenRatio, contentMode: .fit)
        .padding(.bottom, 9)
        .clipShape(RoundedRectangle(cornerRadius: bezelCornerRadius, style: .continuous))
        .zoomingIntoCorner(zoomed, scale: scale, corner: corner)
    }
}

// MARK: -

/// The first-launch and replayable onboarding tour: a sequence of feature
/// slides shown inside a stylized MacBook frame.
struct OnboardingSheet: View {
    /// Called when the tour is dismissed.
    var onDismiss: () -> Void

    @State private var currentSlide = 0
    @State private var zoomed = false
    @State private var zoomGeneration = 0

    @StateObject private var managementModel = ManagementMockupModel()
    @StateObject private var appearanceModel = AppearanceMockupModel()
    @StateObject private var hotkeysModel = HotkeysMockupModel()
    @StateObject private var profilesModel = ProfilesMockupModel()

    private let slides = OnboardingSlide.allCases
    private var isFirst: Bool {
        currentSlide == 0
    }

    private var isLast: Bool {
        currentSlide == slides.count - 1
    }

    private var current: OnboardingSlide {
        slides[currentSlide]
    }

    private var zoomSpec: OnboardingZoomSpec {
        current == .welcome ? .none : .featureTour
    }

    var body: some View {
        VStack(spacing: 0) {
            navRow

            // Welcome shows the app icon; every other slide shows its feature
            // mockup inside the MacBook frame. The laptop zooms into the
            // relevant corner of its screen as a single object — the HUD
            // floats outside it, pinned in place, so it never zooms.
            Group {
                if current == .welcome {
                    OnboardingWelcomeMockup()
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                } else {
                    ZStack(alignment: .bottom) {
                        MacBookBezelView(zoomed: zoomed, scale: zoomSpec.scale, corner: zoomSpec.corner) {
                            ZStack {
                                ForEach(slides) { slide in
                                    if slide != .welcome, slide.rawValue == currentSlide {
                                        screenContent(for: slide)
                                            .transition(.opacity)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 28)

                        ZStack {
                            ForEach(slides) { slide in
                                if slide != .welcome, slide.rawValue == currentSlide {
                                    hudContent(for: slide)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .padding(.bottom, 14)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            .padding(.top, 4)
            .frame(height: 280)
            .clipped()
            .onAppear { restartCurrentSlide() }
            .onChange(of: currentSlide) { _, _ in restartCurrentSlide() }

            bottomArea
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 24)
        }
        .frame(width: 760, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .interactiveDismissDisabled(true)
        .onKeyDown(key: .rightArrow) { advance(); return .handled }
        .onKeyDown(key: .leftArrow) { goBack(); return .handled }
    }

    // MARK: Navigation row

    private var navRow: some View {
        HStack {
            Button { goBack() } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1.5)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .opacity(isFirst ? 0 : 1)

            Spacer()

            if !isLast {
                Button("Skip") {
                    withAnimation(.snappy) { currentSlide = slides.count - 1 }
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Button {
                if isLast {
                    finishOnboarding()
                } else {
                    closeOnboarding()
                }
            } label: {
                Image(systemName: isLast ? "checkmark" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Bottom area

    private var bottomArea: some View {
        VStack(spacing: 14) {
            OnboardingPageIndicator(totalPages: slides.count, currentPage: currentSlide)

            VStack(spacing: 7) {
                ZStack {
                    Text(current.title)
                        .id("title-\(currentSlide)")
                        .transition(.opacity)
                }
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

                ZStack {
                    Text(current.description)
                        .id("desc-\(currentSlide)")
                        .transition(.opacity)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            }

            Button {
                if isLast { finishOnboarding() } else { advance() }
            } label: {
                Text(isLast ? "Get Started" : "Continue")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
        }
    }

    // MARK: Mockup routing

    @ViewBuilder
    private func screenContent(for slide: OnboardingSlide) -> some View {
        switch slide {
        case .welcome: EmptyView()
        case .menuBarManagement: ManagementScreen(model: managementModel)
        case .menuBarAppearance: AppearanceScreen(model: appearanceModel)
        case .hotkeysAutomation: HotkeysScreen(model: hotkeysModel)
        case .profiles: ProfilesScreen(model: profilesModel)
        }
    }

    @ViewBuilder
    private func hudContent(for slide: OnboardingSlide) -> some View {
        switch slide {
        case .welcome: EmptyView()
        case .menuBarManagement: ManagementHUD(model: managementModel)
        case .menuBarAppearance: AppearanceHUD(model: appearanceModel)
        case .hotkeysAutomation: HotkeysHUD(model: hotkeysModel)
        case .profiles: ProfilesHUD(model: profilesModel)
        }
    }

    // MARK: Helpers

    /// The MacBook zooms in once — the first time the tour reaches a feature
    /// slide — and then stays zoomed for the rest of the slides; only the
    /// screen content and HUD crossfade on subsequent navigation. Stepping
    /// back to the welcome slide resets the zoom so it can replay on re-entry.
    private func restartCurrentSlide() {
        zoomGeneration += 1
        let thisZoomGen = zoomGeneration

        if current == .welcome {
            var resetTransaction = Transaction(animation: nil)
            resetTransaction.disablesAnimations = true
            withTransaction(resetTransaction) { zoomed = false }
        } else if !zoomed {
            delay(0.35) {
                guard zoomGeneration == thisZoomGen, current != .welcome else { return }
                withAnimation(.spring(duration: 0.7, bounce: 0.1)) { zoomed = true }
            }
        }

        switch current {
        case .welcome: break
        case .menuBarManagement: managementModel.restart()
        case .menuBarAppearance: appearanceModel.restart()
        case .hotkeysAutomation: hotkeysModel.restart()
        case .profiles: profilesModel.restart()
        }
    }

    /// Steps to the next slide, unless already on the last one.
    private func advance() {
        guard !isLast else { return }
        withAnimation(.snappy) { currentSlide += 1 }
    }

    /// Steps to the previous slide, unless already on the first one.
    private func goBack() {
        guard !isFirst else { return }
        withAnimation(.snappy) { currentSlide -= 1 }
    }

    /// Closes the tour early, from any slide before the last.
    private func closeOnboarding() {
        finishOnboarding()
    }

    /// Completes and dismisses the tour.
    private func finishOnboarding() {
        Defaults.set(true, forKey: .hasSeenOnboarding)
        onDismiss()
    }
}
