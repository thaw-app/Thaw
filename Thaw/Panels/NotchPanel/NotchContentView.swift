//
//  NotchContentView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Animate inside the panel frame; move and resize the panel only while nothing is drawn.
struct NotchContentView: View {
    @ObservedObject var model: NotchPanelModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            if let presentation = model.presentation {
                // Tie the shared raised shadow to visibility so it fades with the reveal.
                silhouette(for: presentation)
                    .thawGlass(.panel, in: silhouette(for: presentation))
                    .thawShadow(.raised, isVisible: model.isRevealed)

                presentation.widget.body
                    .frame(
                        width: presentation.bodySize.width,
                        height: presentation.bodySize.height
                    )
                    .offset(x: presentation.bodyOffset)
                    // Delay text until the descent leaves enough room for it.
                    .opacity(model.isRevealed ? 1 : 0)
                    // The delayed reveal fade finishes with the descent; no shared token covers that timing.
                    .thawAnimation(
                        model.isRevealed
                            ? .easeOut(duration: 0.16).delay(0.1)
                            : ThawMotion.instant,
                        value: model.isRevealed
                    )
                    .allowsHitTesting(model.isRevealed)
                    .onHover { hovering in
                        // Retract on body exit even if the pointer monitor misses it.
                        if !hovering, model.isRevealed {
                            model.setRevealed(false)
                        }
                    }
            }
        }
        // Stronger damping than ThawMotion.interactive avoids a visible bounce at the bar seam.
        .thawAnimation(.spring(response: 0.28, dampingFraction: 0.9), value: model.isRevealed)
    }

    /// Vibrancy and a hairline join the body visually to the bar; zero body height leaves only its underside at rest.
    private func silhouette(for presentation: NotchPresentation) -> NotchShape {
        NotchShape(
            bodyWidth: presentation.bodySize.width,
            bodyOffset: presentation.bodyOffset,
            bodyHeight: model.isRevealed ? presentation.bodySize.height : 0,
            shoulderRadius: NotchMetrics.shoulderRadius,
            bottomRadius: NotchMetrics.bottomRadius
        )
    }
}
