//
//  ThawPillPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// A few choices in one glass capsule, each as wide as its label, like the toggles
/// in Xcode's toolbar. It sits in a row beside its label, where ThawTabStrip would
/// fill the page. With symbols and no titles it is an icon toggle, and the titles
/// stay on as help and for VoiceOver.
public struct ThawPillPicker<Value: Hashable>: View {
    public struct Option {
        let value: Value
        let title: LocalizedStringKey
        let systemImage: String?
        let help: LocalizedStringKey?

        public init(_ value: Value, title: LocalizedStringKey, systemImage: String? = nil, help: LocalizedStringKey? = nil) {
            self.value = value
            self.title = title
            self.systemImage = systemImage
            self.help = help
        }
    }

    @Binding private var selection: Value
    let options: [Option]
    let label: LocalizedStringKey?
    private let showsTitles: Bool

    public init(selection: Binding<Value>, options: [Option], showsTitles: Bool = true) {
        _selection = selection
        self.options = options
        label = nil
        self.showsTitles = showsTitles
    }

    /// A labelled row: the label beside the pills in a LabeledContent, and the
    /// pills' VoiceOver label.
    public init(_ label: LocalizedStringKey, selection: Binding<Value>, options: [Option], showsTitles: Bool = true) {
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
                .init(value: option.value, title: option.title, systemImage: option.systemImage, help: option.help ?? option.title)
            },
            sizing: .fitted(showsTitles: showsTitles)
        )
    }
}
