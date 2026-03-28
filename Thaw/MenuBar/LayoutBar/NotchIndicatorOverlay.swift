//
//  NotchIndicatorOverlay.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A visual indicator overlay showing the notch dead zone in the Layout Bar.
///
/// Displayed at the left edge of the visible section's bar to represent
/// the area where menu bar items cannot be placed on notched displays.
struct NotchIndicatorOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            if let screen = NSScreen.main,
               let notch = screen.frameOfNotch
            {
                let notchGap = MenuBarSection.notchGap
                let screenWidth = screen.frame.width
                let notchTotalWidth = notch.width + 2 * notchGap
                let usableRightWidth = screenWidth - notch.maxX - notchGap

                // Proportional width relative to the usable space right of the notch.
                let proportionalWidth = max(
                    30,
                    geometry.size.width * notchTotalWidth / max(usableRightWidth, 1)
                )
                // Cap at 30% of the bar width to avoid overwhelming the view.
                let clampedWidth = min(proportionalWidth, geometry.size.width * 0.3)

                HStack(spacing: 0) {
                    notchIndicator
                        .frame(width: clampedWidth)
                        .frame(maxHeight: .infinity)
                    Spacer()
                }
            }
        }
    }

    private var notchIndicator: some View {
        ZStack {
            // Diagonal white stripes.
            DiagonalStripes()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(3)

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.secondary.opacity(0.4), lineWidth: 1)
                .padding(3)

            Text("Notch")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Draws repeating diagonal stripes.
private struct DiagonalStripes: View {
    var body: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 3
            let gap: CGFloat = 5
            let step = stripeWidth + gap
            let color = Color.white.opacity(0.25)

            // Draw diagonal lines from bottom-left to top-right across the canvas.
            // Extend the range to cover corners.
            let extent = size.width + size.height
            var offset: CGFloat = -extent

            while offset < extent {
                var path = Path()
                path.move(to: CGPoint(x: offset, y: size.height))
                path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                path.addLine(to: CGPoint(x: offset + size.height + stripeWidth, y: 0))
                path.addLine(to: CGPoint(x: offset + stripeWidth, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(color))
                offset += step
            }
        }
    }
}
