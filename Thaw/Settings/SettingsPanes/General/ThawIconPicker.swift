//
//  ThawIconPicker.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import SwiftUI
import ThawUI

/// The menu bar icon picker, including the custom-image importer and the
/// template-rendering toggle that only applies to a custom icon.
///
/// Extracted from GeneralSettingsPane so Simple Mode can present the same
/// control: choosing the icon is one of the few things a Simple Mode user still
/// wants, and a second copy would be a second thing to keep in sync.
struct ThawIconPicker: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: GeneralSettings

    @State private var isImportingCustomThawIcon = false
    @State private var presentedError: LocalizedErrorWrapper?

    var body: some View {
        let labelKey: LocalizedStringKey = "\(Constants.displayName) icon"

        ThawMenu(labelKey) {
            ForEach(ControlItemImageSet.userSelectableThawIcons) { imageSet in
                Button {
                    settings.thawIcon = imageSet
                    reportIconPersistenceFailure()
                } label: {
                    menuItem(for: imageSet)
                }
            }
            if let lastCustomThawIcon = settings.lastCustomThawIcon {
                Button {
                    settings.thawIcon = lastCustomThawIcon
                    reportIconPersistenceFailure()
                } label: {
                    menuItem(for: lastCustomThawIcon)
                }
            }

            Divider()

            Button("Choose image…") {
                isImportingCustomThawIcon = true
            }
        } title: {
            menuItem(for: settings.thawIcon)
        }
        .annotation("Choose a custom icon to show in the menu bar.")
        .fileImporter(
            isPresented: $isImportingCustomThawIcon,
            allowedContentTypes: [.image]
        ) { result in
            do {
                let url = try result.get()
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    settings.thawIcon = ControlItemImageSet(name: .custom, image: .data(data))
                    reportIconPersistenceFailure()
                }
            } catch {
                presentedError = LocalizedErrorWrapper(error)
            }
        }
        .errorAlert($presentedError)

        if case .custom = settings.thawIcon.name {
            Toggle("Custom icon uses dynamic appearance", isOn: $settings.customThawIconIsTemplate)
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

    /// Reports an icon the settings model could not write. Without this the
    /// menu bar shows the chosen icon while the stored one is unchanged, and
    /// the choice is gone after the next launch with nothing said.
    private func reportIconPersistenceFailure() {
        guard let error = settings.takeThawIconPersistenceError() else { return }
        presentedError = LocalizedErrorWrapper(error)
    }

    private func menuItem(for imageSet: ControlItemImageSet) -> some View {
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
