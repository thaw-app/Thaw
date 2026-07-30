//
//  AboutSettingsPane.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

struct AboutSettingsPane: View {
    @ObservedObject var updatesManager: UpdatesManager
    @Environment(\.openURL) private var openURL

    private static let iconSize: CGFloat = 180
    private static let iconCenter = iconSize / 2

    @State private var iconHoverLocation = CGPoint(x: iconCenter, y: iconCenter)
    @State private var iconIsHovering = false

    var body: some View {
        IceForm {
            mainContent
            Spacer()
            bottomBar
        }
    }

    private var mainContent: some View {
        IceSection(options: [.isBordered]) {
            VStack(spacing: 24) {
                appIconAndCopyrightSection
                updatesSection
            }
            .padding(.vertical, 8)
        }
    }

    private func copyVersionInfo(_ text: LocalizedStringResource) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(String(localized: text), forType: .string)
    }

    private var appIconAndCopyrightSection: some View {
        HStack(spacing: 10) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                let center = Self.iconCenter
                let tiltX = iconIsHovering ? (iconHoverLocation.y - center) / center * -14 : 0
                let tiltY = iconIsHovering ? (iconHoverLocation.x - center) / center * 14 : 0
                let shadowX = iconIsHovering ? (iconHoverLocation.x - center) / center * -10 : 0
                let shadowY = iconIsHovering ? (iconHoverLocation.y - center) / center * -10 : 0

                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .shadow(
                        color: .black.opacity(iconIsHovering ? 0.28 : 0.08),
                        radius: iconIsHovering ? 22 : 6,
                        x: shadowX,
                        y: shadowY
                    )
                    .animation(.interactiveSpring(duration: 0.25), value: iconHoverLocation)
                    .animation(.easeInOut(duration: 0.2), value: iconIsHovering)
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            iconIsHovering = true
                            iconHoverLocation = location
                        case .ended:
                            withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                                iconIsHovering = false
                                iconHoverLocation = CGPoint(x: Self.iconCenter, y: Self.iconCenter)
                            }
                        }
                    }
            }
            VStack(alignment: .leading) {
                Text(verbatim: Constants.displayName)
                    .font(.system(size: 60))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    let versionText = LocalizedStringResource("Version \(Constants.versionString) (\(Constants.buildString))")

                    Text(versionText)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button {
                        copyVersionInfo(versionText)
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
            .disabled(!updatesManager.canCheckForUpdates)

            Spacer()

            Text("Last checked: \(updatesManager.lastUpdateCheckDate?.formatted(date: .abbreviated, time: .standard) ?? String(localized: "Never"))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(updatesManager.lastUpdateCheckDate == nil ? 0.75 : 1.0)
        }
    }

    private var bottomBar: some View {
        IceSection(options: [.isBordered]) {
            HStack(spacing: 0) {
                Button("Quit \(Constants.displayName)") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 20) {
                    Button("Acknowledgements") {
                        if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Contribute") { openURL(Constants.repositoryURL) }
                    Button("Report a Bug") { openURL(Constants.issuesURL) }
                    Button("Support \(Constants.displayName)", systemImage: "heart.circle.fill") {
                        openURL(Constants.donateURL)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}
