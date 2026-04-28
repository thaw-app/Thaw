//
//  NotchIndicatorOverlay.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import SwiftUI

/// A non-interactive view that visualises the notch dead zone at the
/// leading edge of the visible Layout Bar.
///
/// Lives inside the scrollable document view and is sized in real screen
/// points so it scrolls with the layout content and stays in 1:1 scale
/// with the menu bar items beside it.
final class NotchIndicatorView: NSView {
    /// Colour palette used to keep the indicator legible against the
    /// current menu bar background.
    var averageColorInfo: MenuBarAverageColorInfo? {
        didSet {
            hosting.rootView = NotchIndicatorContent(averageColorInfo: averageColorInfo)
        }
    }

    private let hosting: NSHostingView<NotchIndicatorContent>

    init(averageColorInfo: MenuBarAverageColorInfo?) {
        self.averageColorInfo = averageColorInfo
        self.hosting = NSHostingView(rootView: NotchIndicatorContent(averageColorInfo: averageColorInfo))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        unregisterDraggedTypes()

        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// SwiftUI body for the notch indicator. Hosted in `NSHostingView` so the
/// parent `NSView` supplies the frame in real screen points instead of
/// relying on `GeometryReader` math.
private struct NotchIndicatorContent: View {
    let averageColorInfo: MenuBarAverageColorInfo?

    var body: some View {
        ZStack {
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

    private var stripeColor: Color {
        isBright ? .black.opacity(0.5) : .white.opacity(0.5)
    }

    private var borderColor: Color {
        isBright ? .black.opacity(0.65) : .white.opacity(0.65)
    }

    private var textColor: Color {
        isBright ? .black : .white
    }

    private var textPillBackgroundColor: Color {
        guard let colorInfo = averageColorInfo else {
            return Color(nsColor: .defaultLayoutBar)
        }
        return Color(cgColor: colorInfo.color)
    }

    private var isBright: Bool {
        guard let colorInfo = averageColorInfo else { return false }
        return colorInfo.isBright(for: NSScreen.screenWithActiveMenuBar ?? NSScreen.main)
    }
}

/// Repeating diagonal stripes used as the notch indicator's fill.
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
