//
//  CustomSectionDividerControls.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The image a Custom section divider draws, chosen the way a custom Thaw icon is.
struct CustomSectionDividerControls: View {
    @Bindable var settings: AdvancedSettings

    @State private var isImporting = false
    @State private var presentedError: LocalizedErrorWrapper?

    var body: some View {
        LabeledContent {
            HStack(spacing: ThawSpacing.inset) {
                if let data = settings.customSectionDividerImage, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .renderingMode(settings.customSectionDividerIsTemplate ? .template : .original)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 16)
                        .accessibilityHidden(true)
                }
                Button(settings.customSectionDividerImage == nil ? "Choose Image…" : "Change Image…") {
                    isImporting = true
                }
                .buttonStyle(.settingsGlass)
            }
        } label: {
            Text("Divider image")
        }
        .annotation(settings.customSectionDividerImage == nil
            ? "Dividers show the chevron until you choose an image."
            : "Shown between sections while they are open.")
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            do {
                settings.customSectionDividerImage = try StoredImageData.prepared(result.get().contentsOfPickedFile())
            } catch {
                presentedError = LocalizedErrorWrapper(error)
            }
        }
        .errorAlert($presentedError)

        if settings.customSectionDividerImage != nil {
            Toggle("Match the menu bar's appearance", isOn: $settings.customSectionDividerIsTemplate)
                .annotation("Draws the image in the menu bar's own color, light or dark, and drops its colors.")
        }
    }
}
