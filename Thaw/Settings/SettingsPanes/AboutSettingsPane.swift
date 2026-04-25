//
//  AboutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var updatesManager: UpdatesManager
    @Environment(\.openURL) private var openURL

    private var acknowledgementsURL: URL {
        // swiftlint:disable:next force_unwrapping
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf")!
    }

    private var contributeURL: URL {
        Constants.repositoryURL
    }

    private var issuesURL: URL {
        Constants.issuesURL
    }

    private var donateURL: URL {
        Constants.donateURL
    }

    private var lastUpdateCheckString: String {
        if let date = updatesManager.lastUpdateCheckDate {
            date.formatted(date: .abbreviated, time: .standard)
        } else {
            String(localized: "Never")
        }
    }

    var body: some View {
        contentForm()
    }

    private func contentForm() -> some View {
        IceForm {
            mainContent()
            Spacer()
            bottomBar()
        }
    }

    private func mainContent() -> some View {
        IceSection(options: [.isBordered]) {
            VStack(spacing: 24) {
                appIconAndCopyrightSection
                updatesSection
            }
            .padding(.vertical, 8) // Uses your new 8pt standard for height
        }
    }

    private var appIconAndCopyrightSection: some View {
        IceSection(options: .plain) {
            HStack(spacing: 10) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 230)
                }

                VStack(alignment: .leading) {
                    Text("\(Constants.displayName)")
                        .font(.system(size: 80))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        let versionText = LocalizedStringResource("Version \(Constants.versionString) (\(Constants.buildString))")

                        Text(versionText)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(String(localized: versionText), forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy version info")
                    }

                    Text(Constants.copyrightString)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .fontWeight(.medium)
            }
        }
    }

    private var updatesSection: some View {
        IceSection(options: .hasDividers) {
            automaticallyCheckForUpdates
            automaticallyDownloadUpdates
            updateChannel
            checkForUpdates
        }
        .frame(maxWidth: 600)
    }

    private var automaticallyCheckForUpdates: some View {
        Toggle(
            "Automatically check for updates",
            isOn: $updatesManager.automaticallyChecksForUpdates
        )
    }

    private var automaticallyDownloadUpdates: some View {
        Toggle(
            "Automatically download updates",
            isOn: $updatesManager.automaticallyDownloadsUpdates
        )
    }

    private var updateChannel: some View {
        HStack {
            Text("Update channel")
            Spacer()
            Picker("Update channel", selection: $updatesManager.allowsBetaUpdates) {
                Text("Stable").tag(false)
                Text("Development").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var checkForUpdates: some View {
        HStack {
            Button("Check for Updates") {
                updatesManager.checkForUpdates()
            }
            // Disable the button instead of hiding the whole stack
            .disabled(!updatesManager.canCheckForUpdates)

            Spacer()

            Text("Last checked: \(lastUpdateCheckString)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(updatesManager.lastUpdateCheckDate == nil ? 0.75 : 1.0)
        }
    }

    private func bottomBar() -> some View {
        IceSection(options: [.isBordered]) {
            HStack(spacing: 0) {
                Button("Quit \(Constants.displayName)") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 20) {
                    Button("Acknowledgements") { NSWorkspace.shared.open(acknowledgementsURL) }
                    Button("Contribute") { openURL(contributeURL) }
                    Button("Report a Bug") { openURL(issuesURL) }
                    Button("Support \(Constants.displayName)", systemImage: "heart.circle.fill") {
                        openURL(donateURL)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
    }
}
