//
//  SettingsSearchField.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.

import SwiftUI

/// The arrow keys and Return for an app whose results keep a highlight.
public struct SettingsSearchKeyboard {
    let isSearching: Bool
    let previousLabel: LocalizedStringResource
    let nextLabel: LocalizedStringResource
    let move: (_ offset: Int) -> Void
    let submit: () -> Void

    /// isSearching holds the arrow keys during a search; otherwise the sidebar and pages get them. The labels name their
    /// actions. move shifts the highlight by a result count, negative for up. submit opens that result on Return.
    public init(
        isSearching: Bool,
        previousLabel: LocalizedStringResource,
        nextLabel: LocalizedStringResource,
        move: @escaping (_ offset: Int) -> Void,
        submit: @escaping () -> Void
    ) {
        self.isSearching = isSearching
        self.previousLabel = previousLabel
        self.nextLabel = nextLabel
        self.move = move
        self.submit = submit
    }
}

/// Puts the search field in the settings window, with ⌘F from anywhere in it landing in the field.
struct SettingsSearchField: ViewModifier {
    @Binding var text: String
    let placement: SearchFieldPlacement
    let prompt: LocalizedStringResource
    let findLabel: LocalizedStringResource
    let keyboard: SettingsSearchKeyboard?

    /// Whether the search field has focus. Driven by ⌘F; the system clears it on Escape or
    /// when the field loses focus.
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .searchable(text: $text, isPresented: $isPresented, placement: placement, prompt: Text(prompt))
            .onSubmit(of: .search) { keyboard?.submit() }
            .background {
                Button(findLabel) {
                    isPresented = true
                }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                // The arrows walk the results while the field keeps the typing.
                if let keyboard, keyboard.isSearching {
                    Button(keyboard.previousLabel) { keyboard.move(-1) }
                        .keyboardShortcut(.upArrow, modifiers: [])
                        .hidden()
                    Button(keyboard.nextLabel) { keyboard.move(1) }
                        .keyboardShortcut(.downArrow, modifiers: [])
                        .hidden()
                }
            }
    }
}

public extension View {
    /// Adds the settings search field to the split view it is applied to.
    ///
    /// The placement is where the field sits, the toolbar or the sidebar. The find label is the name of the action on ⌘F.
    /// The keyboard is the arrow keys and Return, for results that keep a highlight.
    func settingsSearchField(
        text: Binding<String>,
        placement: SearchFieldPlacement,
        prompt: LocalizedStringResource,
        findLabel: LocalizedStringResource,
        keyboard: SettingsSearchKeyboard? = nil
    ) -> some View {
        modifier(SettingsSearchField(text: text, placement: placement, prompt: prompt, findLabel: findLabel, keyboard: keyboard))
    }
}
