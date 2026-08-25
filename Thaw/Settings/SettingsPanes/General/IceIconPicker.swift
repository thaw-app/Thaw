//
//  IceIconPicker.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The menu bar icon picker, including the custom-image importer and the
/// template-rendering toggle that only applies to a custom icon.
///
/// Extracted from ``GeneralSettingsPane`` (mirroring thaw-next's
/// `ThawIconPicker`) so Simple Mode can present the same control: choosing
/// the icon is one of the few things a Simple Mode user still wants, and a
/// second copy would be a second thing to keep in sync.
struct IceIconPicker: View {
    @Environment(AppState.self) private var appState: AppState
    @Bindable var settings: GeneralSettings

    @State private var isImportingCustomIceIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?

    var body: some View {
        let labelKey: LocalizedStringKey = "\(Constants.displayName) icon"

        IceMenu(labelKey) {
            ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                Button {
                    settings.iceIcon = imageSet
                } label: {
                    iceIconMenuItem(for: imageSet)
                }
            }
            if let lastCustomIceIcon = settings.lastCustomIceIcon {
                Button {
                    settings.iceIcon = lastCustomIceIcon
                } label: {
                    iceIconMenuItem(for: lastCustomIceIcon)
                }
            }

            Divider()

            Button("Choose image…") {
                isImportingCustomIceIcon = true
            }
        } title: {
            iceIconMenuItem(for: settings.iceIcon)
        }
        .annotation("Choose a custom icon to show in the menu bar.")
        .fileImporter(
            isPresented: $isImportingCustomIceIcon,
            allowedContentTypes: [.image]
        ) { result in
            do {
                let url = try result.get()
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    settings.iceIcon = ControlItemImageSet(name: .custom, image: .data(data))
                }
            } catch {
                presentedError = LocalizedErrorWrapper(error)
                isPresentingError = true
            }
        }
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button("OK") {
                presentedError = nil
                isPresentingError = false
            }
        }

        if case .custom = settings.iceIcon.name {
            Toggle("Custom icon uses dynamic appearance", isOn: $settings.customIceIconIsTemplate)
                .annotation {
                    Text(
                        """
                        Display the icon as a monochrome image that dynamically adjusts to match \
                        the menu bar's appearance. This setting removes all color from the icon, \
                        but ensures consistent rendering with both light and dark backgrounds.
                        """
                    )
                    .padding(.trailing, 50)
                }
        }
    }

    private func iceIconMenuItem(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.localized)
        } icon: {
            if let nsImage = imageSet.hidden.nsImage(for: appState) {
                if imageSet.name == .custom {
                    Image(size: CGSize(width: 18, height: 18)) { context in
                        context.draw(Image(nsImage: nsImage), in: context.clipBoundingRect)
                    }
                } else {
                    Image(nsImage: nsImage)
                }
            }
        }
    }
}
