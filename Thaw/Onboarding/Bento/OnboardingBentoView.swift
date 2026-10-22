//
//  OnboardingBentoView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The last onboarding screen: a bento of what the app does, each card a
/// door into the pane that does it, and one row of controls to pick the
/// mode, answer the update question, and open the app.
///
/// Simple is preselected because most new users want the short page first.
///
/// Writes nothing itself: choices leave through onFinish, so quitting
/// mid-flow leaves no half-set preference.
struct OnboardingBentoView: View {
    /// Whether this screen is last, which it is when the access step is skipped.
    let finishesFlow: Bool
    private let onFinish: (OnboardingOutcome, SettingsNavigationIdentifier?) -> Void

    @State private var simpleMode = true
    @State private var automaticUpdates = true
    /// Flipped one tick after appearance so the entrance has a frame to
    /// animate from.
    @State private var appeared = false

    /// Creates the bento screen.
    /// - Parameters:
    ///   - finishesFlow: Whether this screen ends the flow, which it does
    ///     when the access step is skipped.
    ///   - onFinish: Called once with the user's choices and, when a card
    ///     was clicked, the pane to open. Applying both is the host's job.
    init(
        finishesFlow: Bool,
        onFinish: @escaping (OnboardingOutcome, SettingsNavigationIdentifier?) -> Void
    ) {
        self.finishesFlow = finishesFlow
        self.onFinish = onFinish
    }

    /// Row heights at the default text size; with title, controls and gutters
    /// the four rows total 676 against the window's ideal 680.
    ///
    /// Scaled with Dynamic Type so captions do not clip at Larger Text; the
    /// .contentMinSize window grows to fit.
    @ScaledMetric(relativeTo: .body) private var largeRowHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .body) private var smallRowHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: ThawSpacing.inset) {
            Text("Everything \(Constants.displayName) does")
                .font(ThawType.display)
                .padding(.top, ThawSpacing.section)

            grid
                .padding(.horizontal, ThawSpacing.section)

            controls
                .padding(.horizontal, ThawSpacing.section)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground())
        .onAppear {
            Task { @MainActor in appeared = true }
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: ThawSpacing.gutter, verticalSpacing: ThawSpacing.gutter) {
            // Heights sit on the tiles, not the rows: a modifier on a
            // GridRow wraps it in ModifiedContent, and the grid then
            // lays it out as one cell instead of a row.
            // Two cards a row, so each is half the window wide. Four across
            // left every card too narrow for its demo and caption.
            GridRow {
                tile(.find, index: 0, height: largeRowHeight)
                tile(.style, index: 1, height: largeRowHeight)
            }
            GridRow {
                tile(.reveal, index: 2, height: smallRowHeight)
                tile(.thawBar, index: 3, height: smallRowHeight)
            }
            GridRow {
                tile(.triggers, index: 4, height: smallRowHeight)
                tile(.profiles, index: 5, height: smallRowHeight)
            }
            GridRow {
                tile(.zen, index: 6, height: smallRowHeight)
                tile(.integrations, index: 7, height: smallRowHeight)
            }
        }
    }

    /// A card click leaves Simple Mode off whatever the picker says: the
    /// pane it opens only exists in the full window.
    private func tile(_ demo: BentoDemo, index: Int, height: CGFloat) -> some View {
        BentoTile(demo: demo, index: index, appeared: appeared) {
            finish(simpleMode: false, pane: demo.pane)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var controls: some View {
        HStack(spacing: ThawSpacing.gutter) {
            ThawPillPicker(selection: $simpleMode, options: [
                ThawPillPicker.Option(true, title: "Simple Mode"),
                ThawPillPicker.Option(false, title: "All Settings"),
            ])
            // Held at its labels' size, since both are translated and neither may be cut off.
            .fixedSize()
            .accessibilityLabel(Text("Simple Mode"))

            if Constants.supportsSparkleUpdates {
                Toggle("Check for updates automatically", isOn: $automaticUpdates)
                    .toggleStyle(.thawCheckbox)
            }

            Spacer()

            OnboardingPrimaryButton {
                finish(simpleMode: simpleMode, pane: nil)
            } label: {
                Text(finishesFlow ? "Open \(Constants.displayName)" : "Continue")
            }
        }
    }

    private func finish(simpleMode: Bool, pane: SettingsNavigationIdentifier?) {
        onFinish(
            OnboardingOutcome(simpleMode: simpleMode, automaticUpdates: automaticUpdates),
            pane
        )
    }
}
