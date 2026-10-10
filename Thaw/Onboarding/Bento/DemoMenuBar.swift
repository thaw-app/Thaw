//
//  DemoMenuBar.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI

/// Mirrors Full and Split menu bar shapes; the demo calls Split "Pills" for its separate capsules.
enum DemoBarStyle {
    case regular
    case gradient
    case pills

    /// Painted styles use dark labels over the amber accent in both appearances, like the real bright-tint foreground.
    var labelTint: Color {
        switch self {
        case .regular: .primary
        case .gradient, .pills: .black
        }
    }

    /// Use the user's accent to keep the tinted demo, pane tiles, and search fallbacks on one palette.
    static let paintedFill = Color.accentColor.gradient
}

/// Shared mock menu bar for the find, style, reveal, rules, and zen demos; pills matches the Split shape.
/// SF Symbols replace real captures, so the demo never touches the user's bar or prompts for permission.
struct DemoMenuBar: View {
    var hiddenSymbols: [String]
    var hiddenShown: Bool
    var trailingSymbols: [String]
    var style: DemoBarStyle = .regular
    /// Magnifier position as a fraction of hidden-cluster width; nil hides it and the glyph beneath grows.
    /// The cluster owns this overlay because only it knows its glyph positions.
    var searchSweep: Double?

    private var searchedIndex: Int? {
        guard let searchSweep, !hiddenSymbols.isEmpty else { return nil }
        let index = Int(searchSweep * Double(hiddenSymbols.count))
        return min(max(index, 0), hiddenSymbols.count - 1)
    }

    private var hiddenItemsCluster: some View {
        HStack(spacing: 8) {
            ForEach(Array(hiddenSymbols.enumerated()), id: \.offset) { index, symbol in
                GlassIconBubble(symbol: symbol, size: 24, tint: style.labelTint, showBackground: false)
                    .scaleEffect(searchedIndex == index ? 1.25 : 1)
                    .thawAnimation(ThawMotion.settle, value: searchedIndex == index)
            }
        }
        .overlay {
            if let searchSweep {
                GeometryReader { proxy in
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .thawShadow(.raised)
                        .position(
                            x: proxy.size.width * searchSweep,
                            y: proxy.size.height * 0.85
                        )
                }
            }
        }
        .opacity(hiddenShown ? 1 : 0)
        .offset(x: hiddenShown ? 0 : 16)
        .thawAnimation(ThawMotion.settle, value: hiddenShown)
    }

    /// Drawn, not pressable: a nested button would swallow BentoTile's pane-opening click.
    private var dividerDot: some View {
        Circle()
            .fill(style.labelTint.opacity(0.85))
            .frame(width: 6, height: 6)
            .frame(width: 28, height: 28)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    private var trailingCluster: some View {
        HStack(spacing: 8) {
            ForEach(trailingSymbols, id: \.self) { symbol in
                GlassIconBubble(symbol: symbol, size: 24, tint: style.labelTint, showBackground: false)
            }
            // Use the monospaced metric font directly; thawMetric() would override the demo's tint with secondary.
            Text(Date.now.formatted(.dateTime.hour().minute()))
                .font(ThawType.metric)
                .foregroundStyle(style.labelTint.opacity(0.85))
        }
    }

    var body: some View {
        if style == .pills {
            HStack(spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "apple.logo").font(.system(size: 12, weight: .medium))
                    Text("Finder").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(style.labelTint.opacity(0.9))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(DemoBarStyle.paintedFill, in: Capsule())
                .thawShadow(.raised)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    hiddenItemsCluster
                    dividerDot
                    trailingCluster
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(DemoBarStyle.paintedFill, in: Capsule())
                .thawShadow(.raised)
            }
            .padding(.horizontal, 30)
            .thawAnimation(ThawMotion.settle, value: hiddenSymbols)
        } else {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "apple.logo").font(.system(size: 12, weight: .medium))
                    Text("Finder").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(style.labelTint.opacity(0.85))
                .padding(.leading, 16)

                Spacer(minLength: 12)

                hiddenItemsCluster
                dividerDot
                trailingCluster
                    .padding(.trailing, 16)
            }
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .modifier(DemoBarBackground(style: style))
            .padding(.horizontal, 30)
            .thawAnimation(ThawMotion.settle, value: hiddenSymbols)
        }
    }
}

/// ThawGlass already supplies a hairline and shadow; painted styles need their own shadow to avoid doubling it.
struct DemoBarBackground: ViewModifier {
    let style: DemoBarStyle

    func body(content: Content) -> some View {
        switch style {
        case .regular:
            content.thawGlass(.panel, in: Capsule())
        case .gradient:
            content
                .background(DemoBarStyle.paintedFill, in: Capsule())
                .thawShadow(.raised)
        case .pills:
            content
        }
    }
}

/// Mirrors the tour's ControlHUD labels below each demo bar.
struct SlideHUD<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            // .panel: the HUD floats over the mockup as its own container.
            .thawGlass(.panel, in: Capsule())
    }
}

// MARK: - Integrations

/// Prefer bundled icons, then permission-free Launch Services lookup, then SF Symbols.
/// Compact mode fits the 128-point integration tile without a redundant glass offscreen pass.
struct IntegrationCard: View {
    let appName: String
    let subtitle: String
    let bundledAssetName: String?
    var bundleIdentifier: String?
    let fallbackSymbol: String
    var isCompact = false

    private var iconSide: CGFloat {
        isCompact ? 28 : 52
    }

    /// The app's own icon from Launch Services, when the app is installed.
    private var runtimeIcon: NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var icon: some View {
        Group {
            if let bundledAssetName, NSImage(named: bundledAssetName) != nil {
                Image(bundledAssetName)
                    .resizable()
                    .scaledToFit()
            } else if let runtimeIcon {
                Image(nsImage: runtimeIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: isCompact ? 18 : 28, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: iconSide, height: iconSide)
    }

    private var name: some View {
        Text(appName)
            .font(ThawType.heading)
    }

    private var caption: some View {
        Text(subtitle)
            .font(ThawType.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        if isCompact {
            HStack(spacing: ThawSpacing.row) {
                icon
                VStack(alignment: .leading, spacing: ThawSpacing.hairline) {
                    name
                    caption
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ThawSpacing.inset)
            .padding(.vertical, ThawSpacing.row)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
        } else {
            VStack(spacing: 10) {
                icon
                name
                caption
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .thawGlass(.panel, in: RoundedRectangle(cornerRadius: ThawRadius.card, style: .continuous))
        }
    }
}
