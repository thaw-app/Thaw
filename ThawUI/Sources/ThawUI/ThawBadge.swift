//
//  ThawBadge.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A small capsule status badge: "Notch", "Disconnected", "Customized".
///
/// The shared vocabulary for the pattern: quaternary fill, 6×2 padding,
/// capsule clip. Badges annotate a row, they don't act, anything clickable
/// belongs in a Button.
///
/// Two tones only, on purpose. alpha and beta are conveniences over the
/// tinted tone, not a third one: an experiment's maturity is a state the user
/// opted into, and red and green are the Lab's two readings of "how far along
/// is this".
public struct ThawBadge: View {
    public enum Tone {
        /// Facts about the thing (hardware, connection state).
        case neutral
        /// States the user caused and can undo (an override, a pending edit),
        /// washed with the tint like the accent glass tier but flat: badges
        /// sit inside rows, and glass inside glass reads as noise at this size.
        case tinted(Color)
    }

    /// Marks a feature that may not survive: red, uppercase.
    public static var alpha: ThawBadge {
        ThawBadge("ALPHA", tone: .tinted(.red))
    }

    /// Marks a feature that works but is still settling: green, uppercase.
    public static var beta: ThawBadge {
        ThawBadge("BETA", tone: .tinted(.green))
    }

    private let title: LocalizedStringKey
    private let tone: Tone

    public init(_ title: LocalizedStringKey, tone: Tone = .neutral) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Text(title)
            .font(ThawType.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
