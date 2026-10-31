//
//  UpdateConsentSheet.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import SwiftUI

/// The text of the update consent sheet.
public nonisolated struct UpdateConsentStrings: Sendable {
    public var title: LocalizedStringResource
    public var message: LocalizedStringResource
    public var downloadAutomatically: LocalizedStringResource
    public var checkManually: LocalizedStringResource
    public var checkAutomatically: LocalizedStringResource
    /// What VoiceOver says for the checkbox when it is on.
    public var checkboxOn: LocalizedStringResource
    /// What VoiceOver says for the checkbox when it is off.
    public var checkboxOff: LocalizedStringResource

    public init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        downloadAutomatically: LocalizedStringResource,
        checkManually: LocalizedStringResource,
        checkAutomatically: LocalizedStringResource,
        checkboxOn: LocalizedStringResource,
        checkboxOff: LocalizedStringResource
    ) {
        self.title = title
        self.message = message
        self.downloadAutomatically = downloadAutomatically
        self.checkManually = checkManually
        self.checkAutomatically = checkAutomatically
        self.checkboxOn = checkboxOn
        self.checkboxOff = checkboxOff
    }
}

/// Asks once whether the app may look for updates by itself. The app stores the answer and
/// closes the sheet from either closure.
public struct UpdateConsentSheet: View {
    let strings: UpdateConsentStrings
    private let onEnable: (_ autoDownload: Bool) -> Void
    private let onDisable: () -> Void

    @State private var isProcessing = false
    @State private var autoDownload = true

    public init(
        strings: UpdateConsentStrings,
        onEnable: @escaping (_ autoDownload: Bool) -> Void,
        onDisable: @escaping () -> Void
    ) {
        self.strings = strings
        self.onEnable = onEnable
        self.onDisable = onDisable
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.gutter) {
            Text(strings.title)
                .font(.title2.bold())

            Text(strings.message)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            Toggle(isOn: $autoDownload) {
                Text(strings.downloadAutomatically)
            }
            .toggleStyle(.thawCheckbox(onValue: strings.checkboxOn, offValue: strings.checkboxOff))

            HStack {
                Spacer()
                Button(strings.checkManually) {
                    guard !isProcessing else { return }
                    isProcessing = true
                    onDisable()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isProcessing)
                .buttonStyle(.settingsGlass)
                Button(strings.checkAutomatically) {
                    guard !isProcessing else { return }
                    isProcessing = true
                    onEnable(autoDownload)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing)
                .buttonStyle(.thawProminent)
            }
        }
        .padding(20)
        // Minimum only: the buttons and body copy are translated, and several languages run past 380.
        .frame(minWidth: 380)
    }
}

public extension View {
    /// Presents the consent sheet while isPresented is true. Only its buttons answer it.
    func updateConsentSheet(
        isPresented: Binding<Bool>,
        strings: UpdateConsentStrings,
        onEnable: @escaping (_ autoDownload: Bool) -> Void,
        onDisable: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            UpdateConsentSheet(strings: strings, onEnable: onEnable, onDisable: onDisable)
                .interactiveDismissDisabled()
        }
    }
}
