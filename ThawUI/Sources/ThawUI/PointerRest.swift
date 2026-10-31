//
//  PointerRest.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI

/// Where the pointer rested when the panel opened or a key was last pressed. A row that the keys or
/// a new list slide under a pointer that has not moved since is not marked as hovered.
public final class PointerRest {
    public init() {}

    /// How far the pointer has to move, in points, before rows under it are marked again.
    public static let slack: CGFloat = 2

    private var anchor: CGPoint?
    private var moved = true

    public func rest(at location: CGPoint = NSEvent.mouseLocation) {
        anchor = location
        moved = false
    }

    /// Whether the pointer has left its resting place, which it then stays off until the next rest.
    public func hasMoved(to location: CGPoint = NSEvent.mouseLocation) -> Bool {
        if !moved, let anchor, hypot(location.x - anchor.x, location.y - anchor.y) > Self.slack {
            moved = true
        }
        return moved
    }
}

extension EnvironmentValues {
    /// The launcher's resting pointer. Without one a row is marked whenever the pointer is over it.
    @Entry public var pointerRest: PointerRest?
}

/// Whether the pointer is over the view and has moved since it last rested.
public struct PointerHover: ViewModifier {
    @Binding public var isHovering: Bool

    public init(isHovering: Binding<Bool>) {
        _isHovering = isHovering
    }
    @Environment(\.pointerRest) private var rest

    public func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            let hovering = switch phase {
            case .active: rest?.hasMoved() ?? true
            case .ended: false
            }
            if hovering != isHovering {
                isHovering = hovering
            }
        }
    }
}
