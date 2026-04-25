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
    let averageColorInfo: MenuBarAverageColorInfo?

    /// Trigger to force redraw when screen parameters change.
    @State private var screenChangeTrigger = UUID()

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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenChangeTrigger = UUID()
        }
        .id(screenChangeTrigger)
    }

    private var notchIndicator: some View {
        ZStack {
            // Diagonal stripes adapted to menu bar background.
            DiagonalStripes(color: stripeColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(3)

            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: 1)
                .padding(3)

            Text("Notch")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(textPillBackgroundColor)
                )
        }
    }

    /// Color for diagonal stripes based on menu bar background brightness.
    private var stripeColor: Color {
        let isBright = isBrightForActiveScreen()
        return isBright ? .black.opacity(0.5) : .white.opacity(0.5)
    }

    /// Border color based on menu bar background brightness.
    private var borderColor: Color {
        let isBright = isBrightForActiveScreen()
        return isBright ? .black.opacity(0.65) : .white.opacity(0.65)
    }

    /// Text color based on menu bar background brightness.
    private var textColor: Color {
        let isBright = isBrightForActiveScreen()
        return isBright ? .black : .white
    }

    /// Background color for the text pill, matching the menu bar background.
    private var textPillBackgroundColor: Color {
        guard let colorInfo = averageColorInfo else {
            return Color(nsColor: .defaultLayoutBar)
        }
        return Color(cgColor: colorInfo.color)
    }

    /// Helper to check brightness using the same screen used for notch geometry.
    private func isBrightForActiveScreen() -> Bool {
        guard let colorInfo = averageColorInfo else { return false }
        return colorInfo.isBright(for: NSScreen.main)
    }
}

/// Draws repeating diagonal stripes.
private struct DiagonalStripes: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 3
            let gap: CGFloat = 5
            let step = stripeWidth + gap

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
