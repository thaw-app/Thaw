//
//  ThawGlass.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The Liquid Glass variants Thaw uses, with a material stand-in before
/// macOS 26, where Glass does not exist.
enum ThawGlass {
    case regular
    /// Regular glass that reacts to pointer and touch.
    case interactive
    /// Clear glass washed with tint.
    case clear(tint: Color)

    /// Whether this system draws Liquid Glass.
    nonisolated static var isSupported: Bool {
        if #available(macOS 26.0, *) {
            true
        } else {
            false
        }
    }

    @available(macOS 26.0, *)
    var glass: Glass {
        switch self {
        case .regular: .regular
        case .interactive: .regular.interactive()
        case let .clear(tint): .clear.tint(tint)
        }
    }
}

extension View {
    /// Liquid Glass in shape on macOS 26, a material fill before.
    @ViewBuilder
    func thawGlass(_ variant: ThawGlass = .regular, in shape: some Shape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(variant.glass, in: shape)
        } else {
            switch variant {
            case .regular, .interactive:
                background(.regularMaterial, in: shape)
            case let .clear(tint):
                background(tint, in: shape).background(.ultraThinMaterial, in: shape)
            }
        }
    }

    /// The glass button style on macOS 26, the bordered one before.
    @ViewBuilder
    func thawGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

// MARK: - Scroll Edges

/// The scroll edge effect styles Thaw uses.
enum ThawScrollEdgeEffect {
    case automatic
    case soft

    @available(macOS 26.0, *)
    var style: ScrollEdgeEffectStyle {
        switch self {
        case .automatic: .automatic
        case .soft: .soft
        }
    }
}

extension View {
    /// safeAreaBar on macOS 26, safeAreaInset before, which reserves the
    /// same space without the scroll edge effect.
    @ViewBuilder
    func thawSafeAreaBar(
        edge: VerticalEdge,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: spacing, content: content)
        }
    }

    /// The scroll edge effect on macOS 26. Before, scroll views have none.
    @ViewBuilder
    func thawScrollEdgeEffect(_ effect: ThawScrollEdgeEffect, for edges: Edge.Set) -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(effect.style, for: edges)
        } else {
            self
        }
    }
}

/// A GlassEffectContainer on macOS 26, the bare content before.
struct ThawGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
