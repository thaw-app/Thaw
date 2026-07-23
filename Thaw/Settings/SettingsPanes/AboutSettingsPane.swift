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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private static let iconSize: CGFloat = 180
    private static let iconCenter = iconSize / 2

    @State private var iconHoverLocation = CGPoint(x: iconCenter, y: iconCenter)
    @State private var iconIsHovering = false
    @State private var applicationIcon = AboutSettingsPane.currentApplicationIcon()
    @State private var didCopyVersion = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        // The About page isn't a settings form: it centers the app identity in
        // the page. The detail host uses the same extreme behind-window
        // vibrancy as the sidebar.
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            appIconAndCopyrightContent
            updatesSection
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .onChange(of: colorScheme, initial: true) {
            applicationIcon = Self.currentApplicationIcon()
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
        }
    }

    private static func currentApplicationIcon() -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        return (icon.copy() as? NSImage) ?? icon
    }

    private func copyVersionInfo(_ text: LocalizedStringResource) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(String(localized: text), forType: .string)

        copyFeedbackTask?.cancel()
        didCopyVersion = true
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            didCopyVersion = false
            copyFeedbackTask = nil
        }
    }

    private var versionLabelResource: LocalizedStringResource {
        if #available(macOS 27, *) {
            LocalizedStringResource("\(Constants.macOS27PreviewName) (\(Constants.versionString))(\(Constants.buildString))")
        } else {
            LocalizedStringResource("Version \(Constants.versionString) (\(Constants.buildString))")
        }
    }

    private var appIconAndCopyrightContent: some View {
        HStack(spacing: 10) {
            let center = Self.iconCenter
            let motionIsActive = iconIsHovering && !reduceMotion
            let tiltX = motionIsActive ? (iconHoverLocation.y - center) / center * -14 : 0
            let tiltY = motionIsActive ? (iconHoverLocation.x - center) / center * 14 : 0
            let shadowX = motionIsActive ? (iconHoverLocation.x - center) / center * -10 : 0
            let shadowY = motionIsActive ? (iconHoverLocation.y - center) / center * -10 : 0

            Image(nsImage: applicationIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .shadow(
                    color: .black.opacity(motionIsActive ? 0.28 : 0.08),
                    radius: motionIsActive ? 22 : 6,
                    x: shadowX,
                    y: shadowY
                )
                .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.25), value: iconHoverLocation)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: iconIsHovering)
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
            VStack(alignment: .leading) {
                Text(verbatim: Constants.displayName)
                    .font(.system(size: 60))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    let versionText = versionLabelResource

                    Text(versionText)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button {
                        copyVersionInfo(versionText)
                    } label: {
                        Image(systemName: didCopyVersion ? "checkmark" : "doc.on.doc")
                            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: didCopyVersion)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(didCopyVersion ? "Copied" : "Copy version info")
                    .accessibilityLabel(didCopyVersion ? "Copied" : "Copy version info")
                }

                if #available(macOS 27, *) {
                    Text("Based on Thaw \(Constants.versionString) (\(Constants.buildString))")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }

                Text(Constants.copyrightString)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Support \(Constants.displayName)", systemImage: "heart.circle.fill") {
                        openURL(Constants.donateURL)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("Help translate \(Constants.displayName)") {
                            openURL(Constants.translateURL)
                        }
                        Divider()
                        Button("Acknowledgements", action: openAcknowledgements)
                        Divider()
                        Button("Contribute") {
                            openURL(Constants.repositoryURL)
                        }
                        Button("Report a Bug") {
                            openURL(Constants.issuesURL)
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("More project links")
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .fontWeight(.medium)
        }
    }

    private func openAcknowledgements() {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "pdf") else { return }
        NSWorkspace.shared.open(url)
    }

    private var updatesSection: some View {
        VStack(spacing: 12) {
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
            if #available(macOS 27, *) {
                // macOS 27 ships exclusively through Nightly; the channel is
                // locked so users can't switch to a build without 27 support.
                Text("Nightly")
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Update channel",
                    selection: Binding(
                        get: { updatesManager.updateChannel },
                        set: { updatesManager.updateChannel = $0 }
                    )
                ) {
                    Text("Stable").tag(UpdateChannel.stable)
                    Text("Development").tag(UpdateChannel.beta)
                    Text("Nightly").tag(UpdateChannel.alpha)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            updateButton
        }
    }

    private var updateButton: some View {
        Button {
            updatesManager.checkForUpdates()
        } label: {
            Label("Update", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.settingsGlass)
        .disabled(!updatesManager.canCheckForUpdates)
        .accessibilityLabel("Check for Updates")
    }

    private var checkForUpdates: some View {
        HStack {
            Spacer()

            Text("Last checked: \(updatesManager.lastUpdateCheckDate?.formatted(date: .abbreviated, time: .standard) ?? String(localized: "Never"))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .opacity(updatesManager.lastUpdateCheckDate == nil ? 0.75 : 1.0)
        }
    }
}
