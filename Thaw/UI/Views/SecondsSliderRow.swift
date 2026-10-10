//
//  SecondsSliderRow.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// Share the widest localized label through sliderLabelAlignment so sibling sliders align without caller-managed widths.
struct SliderRow<ValueLabel: View>: View {
    @Environment(\.sliderLabelWidth) private var sharedLabelWidth

    private let title: LocalizedStringKey
    @Binding private var value: Double
    private let bounds: ClosedRange<Double>
    private let step: Double
    @ViewBuilder private let valueLabel: (Double) -> ValueLabel

    init(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double,
        @ViewBuilder valueLabel: @escaping (Double) -> ValueLabel
    ) {
        self.title = title
        _value = value
        self.bounds = bounds
        self.step = step
        self.valueLabel = valueLabel
    }

    var body: some View {
        LabeledContent {
            ThawSlider(value: $value, in: bounds, step: step) {
                valueLabel(value)
            }
        } label: {
            Text(title)
                .frame(minWidth: sharedLabelWidth, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SliderLabelWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                }
        }
    }
}

/// A SliderRow for durations, with the value rendered by SecondsLabel
/// so every delay reads "2.5 seconds" the same way.
struct SecondsSliderRow: View {
    private let title: LocalizedStringKey
    @Binding private var value: Double
    private let bounds: ClosedRange<Double>
    private let step: Double

    init(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double
    ) {
        self.title = title
        _value = value
        self.bounds = bounds
        self.step = step
    }

    var body: some View {
        SliderRow(title, value: $value, in: bounds, step: step) { value in
            SecondsLabel(value: value)
        }
    }
}

// MARK: - More actions

/// Shared overflow menu keeps help text and VoiceOver names consistent across rows.
struct MoreActionsMenu<Content: View>: View {
    private let label: LocalizedStringKey
    private let content: Content

    init(label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        ThawMenu {
            content
        } title: {
            Image(systemName: "ellipsis.circle")
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Label width sharing

/// Collects every label width under a sliderLabelAlignment() container so
/// the rows can all adopt the widest one.
private struct SliderLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension EnvironmentValues {
    /// The width shared by every slider label under a .sliderLabelAlignment().
    @Entry var sliderLabelWidth: CGFloat = 0
}

extension View {
    /// Shares the widest slider label under this view with every
    /// SliderRow and SecondsSliderRow inside it.
    func sliderLabelAlignment() -> some View {
        modifier(SliderLabelAlignmentModifier())
    }
}

private struct SliderLabelAlignmentModifier: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.sliderLabelWidth, width)
            .onPreferenceChange(SliderLabelWidthKey.self) { newWidth in
                width = max(width, newWidth)
            }
    }
}
