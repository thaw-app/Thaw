//
//  ThawBadge.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A small capsule status badge: "Notch", "Disconnected", "Customized". Anything clickable belongs in a Button.
/// Two tones only: alpha and beta are conveniences over the tinted one.
public struct ThawBadge: View {
    public enum Tone {
        /// Facts about the thing (hardware, connection state).
        case neutral
        /// States the user caused and can undo (an override, a pending edit). A flat tint:
        /// badges sit inside rows, and glass inside glass reads as noise at this size.
        case tinted(Color)
    }

    /// Marks a feature that may not survive: red, uppercase.
    public static func alpha(_ title: LocalizedStringResource) -> ThawBadge {
        ThawBadge(title, tone: .tinted(.red))
    }

    /// Marks a feature that works but is still settling: green, uppercase.
    public static func beta(_ title: LocalizedStringResource) -> ThawBadge {
        ThawBadge(title, tone: .tinted(.green))
    }

    let title: LocalizedStringResource
    private let tone: Tone

    public init(_ title: LocalizedStringResource, tone: Tone = .neutral) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Text(title)
            .font(ThawType.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, ThawSpacing.compact)
            .padding(.vertical, ThawSpacing.hairline)
            .background(background, in: Capsule(style: .continuous))
            .overlay {
                if case let .tinted(tint) = tone {
                    Capsule(style: .continuous)
                        .strokeBorder(tint.opacity(0.28), lineWidth: 1)
                }
            }
    }

    private var foreground: AnyShapeStyle {
        switch tone {
        case .neutral: AnyShapeStyle(.secondary)
        case .tinted: AnyShapeStyle(.primary)
        }
    }

    private var background: AnyShapeStyle {
        switch tone {
        case .neutral: AnyShapeStyle(.quaternary)
        case let .tinted(tint): AnyShapeStyle(tint.opacity(0.16))
        }
    }
}
