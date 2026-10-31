//
//  ThawActionGroup.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Related buttons in one glass capsule with a hairline between each. Give the
/// buttons .buttonStyle(.thawGrouped) so they draw flat inside the capsule.
public struct ThawActionGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id {
                        Divider()
                            .frame(height: 16)
                            .accessibilityHidden(true)
                    }
                    subview
                }
            }
        }
        .padding(ThawSpacing.capsuleInset)
        .thawGlass(.control, in: Capsule(style: .continuous))
    }
}

/// A button drawn flat for ThawActionGroup: its label, a capsule under the pointer,
/// and a darker one while pressed.
public struct ThawGroupedButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        GroupedButton(configuration: configuration)
    }

    /// How strongly the capsule under the label is filled: darker while pressed, lighter
    /// under the pointer, and nil when nothing is drawn. A disabled button shows no hover.
    static func fillOpacity(isPressed: Bool, isHovered: Bool, isEnabled: Bool) -> Double? {
        if isPressed {
            return 0.14
        }
        return isHovered && isEnabled ? 0.07 : nil
    }

    private struct GroupedButton: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = Capsule(style: .continuous)
            configuration.label
                .font(ThawType.body)
                .padding(.horizontal, ThawSpacing.inset)
                .frame(minHeight: 26)
                .background {
                    if let opacity = ThawGroupedButtonStyle.fillOpacity(
                        isPressed: configuration.isPressed,
                        isHovered: isHovered,
                        isEnabled: isEnabled
                    ) {
                        shape.fill(.primary.opacity(opacity))
                    }
                }
                .contentShape([.interaction, .focusEffect], shape)
                .opacity(isEnabled ? 1 : ThawInk.disabledOpacity)
                .onHover { isHovered = $0 }
        }
    }
}

public extension ButtonStyle where Self == ThawGroupedButtonStyle {
    /// A button inside ThawActionGroup.
    static var thawGrouped: ThawGroupedButtonStyle {
        ThawGroupedButtonStyle()
    }
}
