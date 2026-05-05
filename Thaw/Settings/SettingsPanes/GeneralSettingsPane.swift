//
//  GeneralSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

@preconcurrency import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: GeneralSettings
    @State private var isImportingCustomIceIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?

    private var rehideIntervalKey: LocalizedStringKey {
        let count = Int(settings.rehideInterval)
        return LocalizedStringKey(String(localized: "\(count) seconds"))
    }

    var body: some View {
        IceForm {
            IceSection {
                appOptions
            }
            IceSection {
                iceIconOptions
            }
            IceSection {
                showOptions
            }
            IceSection {
                rehideOptions
            }
        }
    }

    // MARK: App Options

    private var appOptions: some View {
        LaunchAtLogin.Toggle {
            Text("Launch at Login")
        }
    }

    // MARK: Ice Icon Options

    @ViewBuilder
    private var iceIconOptions: some View {
        showIceIcon
        if settings.showIceIcon {
            iceIconPicker
        }
    }

    private var showIceIcon: some View {
        Toggle("Show \(Constants.displayName) icon", isOn: $settings.showIceIcon)
            .annotation("Show the \(Constants.displayName) icon in the menu bar. Click to show hidden items, double-click for always-hidden, and right-click for settings.")
    }

    @ViewBuilder
    private var iceIconPicker: some View {
        let labelKey: LocalizedStringKey = "\(Constants.displayName) icon"

        IceMenu(labelKey) {
            Picker(labelKey, selection: $settings.iceIcon) {
                ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                    Button {
                        settings.iceIcon = imageSet
                    } label: {
                        iceIconMenuItem(for: imageSet)
                    }
                    .tag(imageSet)
                }
                if let lastCustomIceIcon = settings.lastCustomIceIcon {
                    Button {
                        settings.iceIcon = lastCustomIceIcon
                    } label: {
                        iceIconMenuItem(for: lastCustomIceIcon)
                    }
                    .tag(lastCustomIceIcon)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

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

    // MARK: Show Options

    @ViewBuilder
    private var showOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show on click", isOn: $settings.showOnClick)
                .annotation("Click an empty area of the menu bar to show hidden menu bar items.")

            if settings.showOnClick, appState.settings.advanced.enableAlwaysHiddenSection {
                Toggle("Double-click for always-hidden", isOn: $settings.showOnDoubleClick)
                    .annotation("Double-click an empty area of the menu bar to show always-hidden menu bar items.")
            }
        }
        Toggle("Show on hover", isOn: $settings.showOnHover)
            .annotation("Hover over an empty area of the menu bar to show hidden menu bar items.")
        Toggle("Show on scroll", isOn: $settings.showOnScroll)
            .annotation("Scroll or swipe in the menu bar to show hidden menu bar items.")
    }

    // MARK: Rehide Options

    @ViewBuilder
    private var rehideOptions: some View {
        autoRehide
        if settings.autoRehide {
            rehideStrategyPicker
        }
    }

    private var autoRehide: some View {
        Toggle("Automatically rehide", isOn: $settings.autoRehide)
    }

    private var rehideStrategyPicker: some View {
        VStack {
            IcePicker("Strategy", selection: $settings.rehideStrategy) {
                ForEach(RehideStrategy.allCases) { strategy in
                    Text(strategy.localized).tag(strategy)
                }
            }
            .annotation {
                switch settings.rehideStrategy {
                case .smart:
                    Text("Menu bar items are rehidden using a smart algorithm.")
                case .timed:
                    Text("Menu bar items are rehidden after a fixed amount of time.")
                case .focusedApp:
                    Text("Menu bar items are rehidden when the focused app changes.")
                }
            }

            if case .timed = settings.rehideStrategy {
                IceSlider(
                    rehideIntervalKey,
                    value: $settings.rehideInterval,
                    in: 0 ... 30,
                    step: 1
                )
            }
        }
    }
}
