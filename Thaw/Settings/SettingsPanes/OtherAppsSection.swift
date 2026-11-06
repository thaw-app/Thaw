//
//  OtherAppsSection.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import SwiftUI
import ThawUI
import UniformTypeIdentifiers

/// The apps allowed to change settings with thaw:// links. It sits on
/// Privacy because each entry is a grant, like a permission.
struct OtherAppsSection: View {
    @Bindable var settings: AutomationSettings
    @State private var isChoosingApp = false
    @State private var isShowingAddError = false
    @State private var addErrorMessage = ""

    var body: some View {
        ThawSection("Apps that change settings") {
            Toggle(isOn: $settings.isSettingsURIEnabled) {
                ThawRowLabel(
                    "Let apps change settings",
                    detail: "Apps you approve can change \(Constants.displayName) with thaw:// links. Each new app asks you once."
                )
            }

            if settings.isSettingsURIEnabled {
                ForEach(settings.whitelistedApps) { app in
                    allowedAppRow(app)
                }

                HStack(spacing: ThawSpacing.base) {
                    Button("Choose App…") { isChoosingApp = true }
                        .buttonStyle(.settingsGlass)

                    #if DEBUG
                        Button("Add \(Constants.displayName) (Test)") {
                            settings.addCurrentApp()
                        }
                        .buttonStyle(.settingsGlass)
                    #endif
                }

                if isShowingAddError {
                    Text(addErrorMessage)
                        .font(ThawType.caption)
                        .foregroundStyle(Color.warning)
                }
            }
        }
        .fileImporter(isPresented: $isChoosingApp, allowedContentTypes: [.application]) { result in
            addChosenApp(result)
        }
    }

    private func allowedAppRow(_ app: AutomationSettings.WhitelistedApp) -> some View {
        HStack(spacing: ThawSpacing.row) {
            Group {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app")
                        .foregroundStyle(ThawInk.supporting)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            Text(app.displayName)
                .help(app.bundleId)

            Spacer()

            Button("Remove") {
                settings.removeFromWhitelist(bundleId: app.bundleId)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ThawInk.supporting)
            .accessibilityLabel("Remove \(app.displayName)")
        }
    }

    private func addChosenApp(_ result: Result<URL, Error>) {
        guard let url = try? result.get() else {
            showError("The app could not be selected. Try again.")
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        switch AutomationSettings.choice(forBundleID: bundleID, allowed: settings.whitelistedApps.map(\.bundleId)) {
        case let .add(bundleID):
            guard settings.addToWhitelist(appAt: url, bundleID: bundleID) else {
                showError("“\(FileManager.default.displayName(atPath: url.path))” has no valid code signature, so Thaw can't tell it apart from another app.")
                return
            }
            isShowingAddError = false
        case .alreadyAllowed:
            showError("“\(FileManager.default.displayName(atPath: url.path))” is already allowed.")
        case .noBundleID:
            showError("Choose an application with a bundle identifier.")
        }
    }

    private func showError(_ message: String) {
        addErrorMessage = message
        isShowingAddError = true
    }
}
