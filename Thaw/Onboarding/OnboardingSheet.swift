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
/// slides shown inside a stylized MacBook frame, ending on the permissions
/// decision.
struct OnboardingSheet: View {
    /// Called when the tour is dismissed without going through
    /// ``finishOnboarding()`` — i.e. on a replay, once the user closes it.
    var onDismiss: () -> Void

    @EnvironmentObject var appState: AppState

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

    /// Whether this presentation of the sheet is gating first launch — in
    /// which case its final slide is responsible for deciding how setup
    /// proceeds, rather than simply dismissing.
    private var isFirstLaunchFlow: Bool {
        !Defaults.bool(forKey: .hasCompletedFirstLaunch)
    }

    private var zoomSpec: OnboardingZoomSpec {
        switch current {
        case .welcome, .permissions: .none
        default: .featureTour
        }
    }

    var body: some View {
        Group {
            if current == .permissions, isFirstLaunchFlow {
                // On first launch, this sheet is hosted inside the permissions
                // window itself, and this slide *is* the permissions decision —
                // so show the real window rather than a mockup of it. Its own
                // header, cards, and Quit/Continue actions correctly take over
                // from the tour's nav row and "Get Started" button here.
                //
                // On a replay, though, the decision was already made on first
                // launch and this sheet isn't hosted in that window, so its
                // Quit/Continue actions would target the wrong window — the
                // tour falls through to ``permissionsPreview`` instead.
                PermissionsView<AppPermissions>()
                    .environmentObject(appState.permissions)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            } else {
                VStack(spacing: 0) {
                    navRow

                    // Welcome slide shows just the app icon; the permissions
                    // slide (on a replay) shows a read-only preview of the
                    // permission cards; every other slide shows its feature
                    // mockup inside the MacBook frame. The laptop zooms into
                    // the relevant corner of its screen as a single object —
                    // the HUD floats outside it, pinned in place, so it never
                    // zooms.
                    Group {
                        if current == .welcome {
                            OnboardingWelcomeMockup()
                                .transition(.opacity.combined(with: .scale(scale: 0.99)))
                        } else if current == .permissions {
                            permissionsPreview
                                .transition(.opacity.combined(with: .scale(scale: 0.99)))
                        } else {
                            ZStack(alignment: .bottom) {
                                MacBookBezelView(zoomed: zoomed, scale: zoomSpec.scale, corner: zoomSpec.corner) {
                                    ZStack {
                                        ForEach(slides) { slide in
                                            if slide != .welcome, slide != .permissions, slide.rawValue == currentSlide {
                                                screenContent(for: slide)
                                                    .transition(.opacity)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 28)

                                ZStack {
                                    ForEach(slides) { slide in
                                        if slide != .welcome, slide != .permissions, slide.rawValue == currentSlide {
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
            }
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
                    // Jumps straight to the final, permissions slide rather
                    // than dismissing outright — on first launch that step is
                    // mandatory, and on a replay it's the most useful place
                    // to land if the user just wants to check their access.
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

    // MARK: Permissions preview (replay)

    /// A preview of the permission cards shown when replaying the tour.
    ///
    /// The decision was already made on first launch, and this sheet isn't
    /// hosted inside the permissions window here, so showing the real
    /// ``PermissionsView`` (whose actions target that window) would leave the
    /// slide stuck. The cards themselves are still fully interactive — the
    /// user can grant or check access — they just sit within the tour's own
    /// nav row and "Get Started" button instead of the window's chrome.
    private var permissionsPreview: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 16) {
                ForEach(appState.permissions.allPermissions) { permission in
                    PermissionCard(permission: permission, refocusesWindowAfterGrant: false)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
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

            Button(isLast ? "Get Started" : "Continue") {
                if isLast { finishOnboarding() } else { advance() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.plain)
            .font(.body.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.accentColor)
            .clipShape(Capsule())
        }
    }

    // MARK: Mockup routing

    @ViewBuilder
    private func screenContent(for slide: OnboardingSlide) -> some View {
        switch slide {
        case .welcome, .permissions: EmptyView()
        case .menuBarManagement: ManagementScreen(model: managementModel)
        case .menuBarAppearance: AppearanceScreen(model: appearanceModel)
        case .hotkeysAutomation: HotkeysScreen(model: hotkeysModel)
        case .profiles: ProfilesScreen(model: profilesModel)
        }
    }

    @ViewBuilder
    private func hudContent(for slide: OnboardingSlide) -> some View {
        switch slide {
        case .welcome, .permissions: EmptyView()
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
        } else if current != .permissions, !zoomed {
            delay(0.35) {
                guard zoomGeneration == thisZoomGen, current != .welcome else { return }
                withAnimation(.spring(duration: 0.7, bounce: 0.1)) { zoomed = true }
            }
        }

        switch current {
        case .welcome, .permissions: break
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
    ///
    /// On a replay, this is a plain dismissal. On first launch, though, the
    /// tour can't simply be dismissed — the permissions decision still needs
    /// resolving and setup still needs to run — so closing early falls back
    /// to ``finishOnboarding()``, completing setup with whatever permissions
    /// state currently holds.
    private func closeOnboarding() {
        guard isFirstLaunchFlow else {
            Defaults.set(true, forKey: .hasSeenOnboarding)
            onDismiss()
            return
        }

        // On first launch, the tour gates whether the app ever finishes
        // setting up — closing early without completing it would leave the
        // app running in limbo. Quitting outright (matching the permissions
        // window's own Quit button) is the only sound option here.
        //
        // Deferred to the next default-mode runloop turn: firing it directly
        // from this button action races with the sheet's own dismissal/
        // transition machinery, which can swallow the termination reply and
        // leave the app stuck running (see MenuBarManager.quitFromSecondaryContextMenu
        // for the same pattern under a different cause).
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
    }

    /// Completes the tour from its final, permissions slide.
    ///
    /// On a replay (e.g. from the About pane), this is just a dismissal —
    /// setup already happened on first launch. On first launch, though, this
    /// slide is the moment the user has decided whether to grant permissions,
    /// so it takes over from ``PermissionsView``'s continue button: closing
    /// the permissions window and kicking off setup based on what was granted.
    private func finishOnboarding() {
        guard isFirstLaunchFlow else {
            Defaults.set(true, forKey: .hasSeenOnboarding)
            onDismiss()
            return
        }

        appState.completeFirstLaunchSetup()
    }
}
