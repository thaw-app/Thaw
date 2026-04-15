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
        if #available(macOS 26.0, *) {
            contentForm(cornerStyle: .continuous)
        } else {
            contentForm(cornerStyle: .circular)
        }
    }

    private func contentForm(cornerStyle: RoundedCornerStyle) -> some View {
        IceForm(spacing: 0) {
            mainContent(containerShape: RoundedRectangle(cornerRadius: 20, style: cornerStyle))
            Spacer(minLength: 10)
            bottomBar(containerShape: Capsule(style: cornerStyle))
        }
    }

    private func mainContent(containerShape: some InsettableShape) -> some View {
        IceSection(spacing: 0, options: .plain) {
            appIconAndCopyrightSection
                .layoutPriority(1)

            Spacer(minLength: 0)
                .frame(maxHeight: 20)

            updatesSection
                .layoutPriority(1)
        }
        .padding(.top, 5)
        .padding([.horizontal, .bottom], 30)
        .frame(maxHeight: 500)
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
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

                    Text("Version \(Constants.versionString) (\(Constants.buildString))")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    Text(Constants.copyrightString)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.67))
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
                .opacity(updatesManager.lastUpdateCheckDate == nil ? 0.5 : 1.0)
        }
    }

    private func bottomBar(containerShape: some InsettableShape) -> some View {
        HStack {
            Button("Quit \(Constants.displayName)") {
                NSApp.terminate(nil)
            }
            Spacer()
            Button("Acknowledgements") {
                NSWorkspace.shared.open(acknowledgementsURL)
            }
            Button("Contribute") {
                openURL(contributeURL)
            }
            Button("Report a Bug") {
                openURL(issuesURL)
            }
            Button("Support \(Constants.displayName)", systemImage: "heart.circle.fill") {
                openURL(donateURL)
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        ContainerRelativeShape()
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
