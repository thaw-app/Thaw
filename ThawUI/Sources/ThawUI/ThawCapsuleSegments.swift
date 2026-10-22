//
//  ThawCapsuleSegments.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The glass capsule of segments that ThawPillPicker and ThawTabStrip draw:
/// one plain button per value, the selected one filled and in a heavier weight.
struct ThawCapsuleSegments<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: LocalizedStringKey
        let systemImage: String?
        let help: LocalizedStringKey?
    }

    /// How the capsule and its segments take up space.
    enum Sizing: Equatable {
        /// Each segment as wide as its label, which may be a symbol alone.
        case fitted(showsTitles: Bool)
        /// The segments share the width evenly and the capsule fills its container.
        case filling

        var showsTitles: Bool {
            switch self {
            case let .fitted(showsTitles): showsTitles
            case .filling: true
            }
        }

        var spacing: CGFloat {
            self == .filling ? ThawSpacing.tight : ThawSpacing.hairline
        }

        var inset: CGFloat {
            self == .filling ? ThawSpacing.tight : ThawSpacing.capsuleInset
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .filling: ThawSpacing.inset
            case .fitted(showsTitles: true): ThawSpacing.row
            case .fitted(showsTitles: false): ThawSpacing.compact
            }
        }

        var minWidth: CGFloat? {
            self == .filling ? nil : 28
        }

        var maxWidth: CGFloat? {
            self == .filling ? .infinity : nil
        }

        var minHeight: CGFloat {
            self == .filling ? 30 : 24
        }

        var maxHeight: CGFloat? {
            self == .filling ? 30 : nil
        }
    }

    @Binding var selection: Value
    let segments: [Segment]
    let sizing: Sizing

    var body: some View {
        HStack(spacing: sizing.spacing) {
            ForEach(segments, id: \.value) { segment in
                segmentButton(segment)
            }
        }
        .padding(sizing.inset)
        .frame(maxWidth: sizing.maxWidth)
        .thawGlass(.control, in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let isSelected = segment.value == selection
        let shape = Capsule(style: .continuous)
        // Styled on each part: a section header sets its own text colour over the label's.
        let style = isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
        let weight: Font.Weight = isSelected ? .semibold : .regular
        return Button {
            selection = segment.value
        } label: {
            HStack(spacing: ThawSpacing.tight) {
                if let systemImage = segment.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: weight))
                        .foregroundStyle(style)
                }
                if sizing.showsTitles {
                    Text(segment.title)
                        .font(ThawType.body.weight(weight))
                        .foregroundStyle(style)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.horizontal, sizing.horizontalPadding)
            .frame(
                minWidth: sizing.minWidth,
                maxWidth: sizing.maxWidth,
                minHeight: sizing.minHeight,
                maxHeight: sizing.maxHeight
            )
            .thawSelectedFill(isSelected, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .thawSelectionCue(isSelected: isSelected, in: shape)
        .modifier(SegmentHelp(text: segment.help))
        .accessibilityLabel(Text(segment.title))
    }
}

/// A segment's tooltip, left off entirely when it has none, so an empty one
/// never covers a tooltip set further out.
private struct SegmentHelp: ViewModifier {
    let text: LocalizedStringKey?

    func body(content: Content) -> some View {
        if let text {
            content.help(Text(text))
        } else {
            content
        }
    }
}
