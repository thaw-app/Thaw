//
//  WhatsNewView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

/// The release-notes reader: a ReadingPage whose path is the releases,
/// whose title is the selected release, and whose body is that release's
/// notes. Reuses ChangelogDocument for parsing.
struct WhatsNewView: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState

    @State private var selectedVersion: String?
    @State private var releases: [ChangelogDocument.Release] = []
    @State private var source: ChangelogDocument.Source = .unavailable
    @State private var isLoading = true

    private var selectedRelease: ChangelogDocument.Release? {
        releases.first { $0.version == selectedVersion } ?? releases.first
    }

    var body: some View {
        ReadingPage(
            path: releases.map { ReadingPathItem(id: $0.version, label: $0.version) },
            selection: $selectedVersion,
            title: title,
            subtitle: subtitle
        ) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let release = selectedRelease {
                VStack(alignment: .leading, spacing: 28) {
                    updateNotice(for: release)
                    sourceNotice
                    releaseBody(release)
                }
            } else if source == .disabled {
                Text("Fetching release notes is off in Privacy. Turn on “What’s New notes” there to load them.")
                    .font(ReadingPageType.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(Constants.displayName) couldn’t load the release notes.")
                    .font(ReadingPageType.body)
                    .foregroundStyle(.secondary)
            }
        } links: {
            Button("Full changelog") {
                openURL(Constants.repositoryURL)
            }
            .buttonStyle(.settingsGlass)
            Text(verbatim: "/")
                .foregroundStyle(ThawInk.supporting)
            Button("Experiments") {
                openURL(Constants.labDiscussionURL)
            }
            .buttonStyle(.settingsGlass)
        }
        .task(id: TaskKey(fetch: appState.settings.advanced.fetchReleaseNotes, update: appState.pendingUpdateVersion)) {
            // Fetched when the Privacy switch allows it, otherwise the last
            // fetched copy; nothing is bundled. Only version 3 releases show.
            let allowFetch = appState.settings.advanced.fetchReleaseNotes
            let loaded = await ChangelogDocument.load(allowFetch: allowFetch)
            releases = loaded.document.map { ChangelogDocument.displayReleases(in: $0) } ?? []
            source = loaded.source
            if let update = appState.pendingUpdateVersion, releases.contains(where: { $0.version == update }) {
                selectedVersion = update
            } else if selectedVersion == nil || !releases.contains(where: { $0.version == selectedVersion }) {
                selectedVersion = releases.first?.version
            }
            isLoading = false
        }
    }

    /// Reloads when the Privacy switch flips or an update opens the window,
    /// since the update's notes are newer than any loaded copy.
    private struct TaskKey: Equatable {
        var fetch: Bool
        var update: String?
    }

    /// Marks the notes of an update that is ready but not installed yet.
    @ViewBuilder
    private func updateNotice(for release: ChangelogDocument.Release) -> some View {
        if release.version == appState.pendingUpdateVersion {
            Text("This update is ready to install. Use the update window to install it now or later.")
                .font(ThawType.body)
                .foregroundStyle(.secondary)
        }
    }

    /// Says where the notes came from when that is not the repository, so
    /// a reader looking at older text knows why.
    @ViewBuilder
    private var sourceNotice: some View {
        switch source {
        case .disabled:
            Text("Fetching release notes is off in Privacy, so this is the last copy fetched.")
                .font(ThawType.body)
                .foregroundStyle(.secondary)
        case .cached:
            Text("The repository could not be reached, so this is the last copy fetched.")
                .font(ThawType.body)
                .foregroundStyle(.secondary)
        case .fetched, .unavailable:
            EmptyView()
        }
    }

    private var title: Text {
        if let release = selectedRelease {
            Text("What’s new in \(release.version)")
        } else {
            Text("What’s New")
        }
    }

    private var subtitle: Text? {
        guard let release = selectedRelease else { return nil }
        let date = release.date.map { Text($0, format: .dateTime.day().month(.wide).year()) }
        switch (date, release.facts) {
        case let (date?, facts?): return Text("\(date) · \(facts)")
        case let (date?, nil): return date
        case let (nil, facts?): return Text(verbatim: facts)
        case (nil, nil): return nil
        }
    }

    private func releaseBody(_ release: ChangelogDocument.Release) -> some View {
        VStack(alignment: .leading, spacing: 40) {
            if !release.intro.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(release.intro.enumerated()), id: \.offset) { _, block in
                        releaseBlock(block)
                    }
                }
            }

            if !release.badges.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(release.badges.enumerated()), id: \.offset) { _, badge in
                        badgeButton(badge)
                    }
                }
            }

            ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 20) {
                    Text(verbatim: section.title)
                        .font(ReadingPageType.heading)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(Array(section.themes.enumerated()), id: \.offset) { _, theme in
                        VStack(alignment: .leading, spacing: 12) {
                            if let title = theme.title {
                                Text(verbatim: title)
                                    .font(ReadingPageType.body.weight(.semibold))
                            }
                            ForEach(Array(theme.bullets.enumerated()), id: \.offset) { _, block in
                                themeBlock(block)
                            }
                        }
                    }
                }
            }
        }
        .id(release.version)
        .transition(.opacity)
    }

    /// A release's intro: prose, or an alert, which sits at full width.
    @ViewBuilder
    private func releaseBlock(_ block: ChangelogDocument.Block) -> some View {
        switch block {
        case let .text(text):
            ReadingParagraph(text)
        case let .callout(callout):
            ChangelogCalloutView(callout: callout)
        }
    }

    /// A theme's body: bullets keep their marker, an alert does not.
    @ViewBuilder
    private func themeBlock(_ block: ChangelogDocument.Block) -> some View {
        switch block {
        case let .text(text):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: "•")
                    .foregroundStyle(.tertiary)
                ReadingParagraph(text)
            }
        case let .callout(callout):
            ChangelogCalloutView(callout: callout)
        }
    }

    /// Badge images are bundled, not fetched, so the page keeps the Privacy
    /// pane's promise that nothing here reaches the network.
    @ViewBuilder
    private func badgeButton(_ badge: ChangelogDocument.Badge) -> some View {
        if let image = Self.bundledImage(named: badge.imageFileName) {
            Button {
                openURL(badge.url)
            } label: {
                // Each badge at its own point size: they differ in height.
                Image(nsImage: image)
                    .resizable()
                    .frame(width: image.size.width, height: image.size.height)
            }
            .buttonStyle(.plain)
            .thawHoverLift()
            .accessibilityLabel(badge.alt)
        } else {
            Button(badge.alt) {
                openURL(badge.url)
            }
            .buttonStyle(.plain)
        }
    }

    /// Looks up by name first so AppKit pairs Name.png with Name@2x.png;
    /// a direct file load would draw the 1x bitmap scaled up.
    private static func bundledImage(named fileName: String) -> NSImage? {
        let url = URL(fileURLWithPath: fileName)
        let name = url.deletingPathExtension().lastPathComponent
        if let named = NSImage(named: name) {
            return named
        }
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        guard let resource = Bundle.main.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: resource)
    }
}

/// A GitHub alert from the release notes, on the .accent tier. The symbol and
/// label carry the meaning, so colour is never the only cue.
private struct ChangelogCalloutView: View {
    let callout: ChangelogDocument.Callout

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            Label {
                Text(callout.kind.label)
                    .font(ReadingPageType.body.weight(.semibold))
            } icon: {
                Image(systemName: callout.kind.symbol)
            }
            .foregroundStyle(callout.kind.tint)

            ForEach(Array(callout.parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case let .paragraph(text):
                    ReadingParagraph(text)
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "•")
                            .foregroundStyle(.secondary)
                        ReadingParagraph(text)
                    }
                }
            }
        }
        .padding(ThawSpacing.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.clear
                .thawGlass(.accent(callout.kind.tint), in: shape)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension ChangelogDocument.Callout.Kind {
    var label: LocalizedStringKey {
        switch self {
        case .note: "Note"
        case .tip: "Tip"
        case .important: "Important"
        case .warning: "Warning"
        case .caution: "Caution"
        }
    }

    var symbol: String {
        switch self {
        case .note: "info.circle"
        case .tip: "lightbulb"
        case .important: "exclamationmark.circle"
        case .warning: "exclamationmark.triangle"
        case .caution: "exclamationmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .note, .important: .blue
        case .tip: .green
        case .warning: .orange
        case .caution: .red
        }
    }
}
