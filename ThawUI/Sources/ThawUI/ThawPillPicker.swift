//
//  ThawPillPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// Choices in one glass capsule, each as wide as its label. Without titles, the
/// titles become help and VoiceOver labels.
public struct ThawPillPicker<Value: Hashable>: View {
    public typealias Option = ThawSegment<Value>

    @Binding private var selection: Value
    let options: [Option]
    let label: LocalizedStringKey?
    private let showsTitles: Bool

    /// A label, when given, sits beside the pills in a LabeledContent and is the
    /// pills' VoiceOver label.
    public init(
        _ label: LocalizedStringKey? = nil,
        selection: Binding<Value>,
        options: [Option],
        showsTitles: Bool = true
    ) {
        _selection = selection
        self.options = options
        self.label = label
        self.showsTitles = showsTitles
    }

    /// A labelled row with one pill per value, in order, each named by title.
    public init(
        _ label: LocalizedStringKey,
        selection: Binding<Value>,
        values: some Sequence<Value>,
        title: (Value) -> LocalizedStringKey
    ) {
        self.init(label, selection: selection, options: values.map { Option($0, title: title($0)) })
    }

    public var body: some View {
        if let label {
            LabeledContent(label) {
                segments
                    .accessibilityLabel(Text(label))
            }
        } else {
            segments
        }
    }

    private var segments: some View {
        ThawCapsuleSegments(
            selection: $selection,
            segments: options.map { option in
                Option(option.value, title: option.title, systemImage: option.systemImage, help: option.help ?? option.title)
            },
            sizing: .fitted(showsTitles: showsTitles)
        )
    }
}
