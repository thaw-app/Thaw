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
                let notchTotalWidth = notch.width + 2 * notchGap
                // Total right-side space: from screen center to right edge,
                // which includes both the notch area and the usable area.
                let rightSideTotal = screen.frame.width / 2
                let notchFraction = notchTotalWidth / max(rightSideTotal, 1)

                // The layout bar represents the right side of the screen.
                // Scale the notch proportionally.
                let proportionalWidth = max(30, geometry.size.width * notchFraction)
                // Cap at 45% of the bar width.
                let clampedWidth = min(proportionalWidth, geometry.size.width * 0.45)

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
