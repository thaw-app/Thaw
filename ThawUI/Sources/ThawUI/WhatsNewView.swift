//
//  WhatsNewView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

/// The text of What's New. Each closure fills in values the page only knows when it draws.
public nonisolated struct WhatsNewStrings: Sendable {
    public var title: LocalizedStringResource
    public var releaseTitle: @Sendable (_ version: String) -> LocalizedStringResource
    /// A release's formatted date with its facts line, when it has both.
    public var releaseSubtitle: @Sendable (_ date: Text, _ facts: String) -> Text
    public var noRelease: @Sendable (_ channel: Text, _ appName: String) -> Text
    public var loadFailed: @Sendable (_ appName: String) -> LocalizedStringResource
    /// Fetching is off and there is nothing to show.
    public var fetchingOff: LocalizedStringResource
    /// Fetching is off, so the notes shown are the last copy fetched.
    public var fetchingOffCached: LocalizedStringResource
    public var updateReady: LocalizedStringResource
    public var cachedCopy: LocalizedStringResource
    public var fullChangelog: LocalizedStringResource
    public var older: LocalizedStringResource
    public var channelName: @Sendable (UpdateChannel) -> LocalizedStringResource
    public var calloutName: @Sendable (ChangelogDocument.Callout.Kind) -> LocalizedStringResource

    public init(
        title: LocalizedStringResource,
        releaseTitle: @escaping @Sendable (_ version: String) -> LocalizedStringResource,
        releaseSubtitle: @escaping @Sendable (_ date: Text, _ facts: String) -> Text,
        noRelease: @escaping @Sendable (_ channel: Text, _ appName: String) -> Text,
        loadFailed: @escaping @Sendable (_ appName: String) -> LocalizedStringResource,
        fetchingOff: LocalizedStringResource,
        fetchingOffCached: LocalizedStringResource,
        updateReady: LocalizedStringResource,
        cachedCopy: LocalizedStringResource,
        fullChangelog: LocalizedStringResource,
        older: LocalizedStringResource,
        channelName: @escaping @Sendable (UpdateChannel) -> LocalizedStringResource,
        calloutName: @escaping @Sendable (ChangelogDocument.Callout.Kind) -> LocalizedStringResource
    ) {
        self.title = title
        self.releaseTitle = releaseTitle
        self.releaseSubtitle = releaseSubtitle
        self.noRelease = noRelease
        self.loadFailed = loadFailed
        self.fetchingOff = fetchingOff
        self.fetchingOffCached = fetchingOffCached
        self.updateReady = updateReady
        self.cachedCopy = cachedCopy
        self.fullChangelog = fullChangelog
        self.older = older
        self.channelName = channelName
        self.calloutName = calloutName
    }
}

/// The release-notes reader: a ReadingPage whose path is the releases, and whose title and body are the selected release's.
public struct WhatsNewView: View {
    @Environment(\.openURL) private var openURL
    private let info: ThawAppInfo
    private let allowFetch: Bool
    private let pendingUpdateVersion: String?
    let strings: WhatsNewStrings

    public init(
        info: ThawAppInfo,
        strings: WhatsNewStrings,
        allowFetch: Bool = true,
        pendingUpdateVersion: String? = nil
    ) {
        self.info = info
        self.strings = strings
        self.allowFetch = allowFetch
        self.pendingUpdateVersion = pendingUpdateVersion
        _channel = State(initialValue: UpdateChannel(version: info.version))
    }

    @State private var selectedVersion: String?
    /// Every shown release, newest first; the path shows the chosen channel's.
    @State private var releases: [ChangelogDocument.Release] = []
    /// Opens on the running build's channel, so the newest notes for this Mac come first.
    @State private var channel: UpdateChannel
    @State private var source: ChangelogDocument.Source = .unavailable
    @State private var isLoading = true

    private var channelReleases: [ChangelogDocument.Release] {
        guard info.showsChannels else { return releases }
        return releases.filter { UpdateChannel(version: $0.version) == channel }
    }

    private var selectedRelease: ChangelogDocument.Release? {
        channelReleases.first { $0.version == selectedVersion } ?? channelReleases.first
    }

    public var body: some View {
        ReadingPage(
            appName: info.displayName,
            path: channelReleases.map { ReadingPathItem(id: $0.version, label: $0.version) },
            selection: $selectedVersion,
            title: title,
            subtitle: subtitle,
            olderLabel: strings.older
        ) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if !releases.isEmpty {
                VStack(alignment: .leading, spacing: 28) {
                    if info.showsChannels {
                        channelPicker
                    }
                    if let release = selectedRelease {
                        updateNotice(for: release)
                        sourceNotice
                        releaseBody(release)
                    } else {
                        strings.noRelease(Text(strings.channelName(channel)), info.displayName)
                            .font(ReadingPageType.body)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if source == .disabled {
                Text(strings.fetchingOff)
                    .font(ReadingPageType.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(strings.loadFailed(info.displayName))
                    .font(ReadingPageType.body)
                    .foregroundStyle(.secondary)
            }
        } links: {
            Button(strings.fullChangelog) {
                openURL(info.releasesURL)
            }
            .buttonStyle(.settingsGlass)
        }
        .task(id: TaskKey(fetch: allowFetch, update: pendingUpdateVersion)) {
            // Fetched when the Privacy switch allows it, otherwise the last fetched copy; nothing is bundled.
            let loaded = await ChangelogDocument.load(allowFetch: allowFetch, info: info)
            // A newer task owns the state now; this load's result is stale.
            guard !Task.isCancelled else { return }
            releases = loaded.document.map { ChangelogDocument.displayReleases(in: $0, majorVersion: info.shownMajorVersion) } ?? []
            source = loaded.source
            if let update = pendingUpdateVersion, releases.contains(where: { $0.version == update }) {
                channel = UpdateChannel(version: update)
                selectedVersion = update
            } else if selectedVersion == nil || !releases.contains(where: { $0.version == selectedVersion }) {
                selectedVersion = channelReleases.first?.version
            }
            isLoading = false
        }
    }

    /// Tabs: ThawUI's style guard keeps segmented controls off Settings pages.
    private var channelPicker: some View {
        ThawTabStrip(
            selection: Binding(
                get: { channel },
                set: { newChannel in
                    channel = newChannel
                    selectedVersion = channelReleases.first?.version
                }
            ),
            items: UpdateChannel.allCases.map { .init($0, title: strings.channelName($0), systemImage: $0.systemImage) }
        )
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
        if release.version == pendingUpdateVersion {
            Text(strings.updateReady)
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
            Text(strings.fetchingOffCached)
                .font(ThawType.body)
                .foregroundStyle(.secondary)
        case .cached:
            Text(strings.cachedCopy)
                .font(ThawType.body)
                .foregroundStyle(.secondary)
        case .fetched, .unavailable:
            EmptyView()
        }
    }

    private var title: Text {
        if let release = selectedRelease {
            Text(strings.releaseTitle(release.version))
        } else {
            Text(strings.title)
        }
    }

    private var subtitle: Text? {
        guard let release = selectedRelease else { return nil }
        let date = release.date.map { Text($0, format: .dateTime.day().month(.wide).year()) }
        switch (date, release.facts) {
        case let (date?, facts?): return strings.releaseSubtitle(date, facts)
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
                HStack(spacing: ThawSpacing.gutter) {
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
                        VStack(alignment: .leading, spacing: ThawSpacing.inset) {
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
            ChangelogCalloutView(callout: callout, label: strings.calloutName(callout.kind))
        }
    }

    /// A theme's body: bullets keep their marker, an alert does not.
    @ViewBuilder
    private func themeBlock(_ block: ChangelogDocument.Block) -> some View {
        switch block {
        case let .text(text):
            HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.inset) {
                Text(verbatim: "•")
                    .foregroundStyle(.tertiary)
                ReadingParagraph(text)
            }
        case let .callout(callout):
            ChangelogCalloutView(callout: callout, label: strings.calloutName(callout.kind))
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
    let label: LocalizedStringResource

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ThawRadius.control, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ThawSpacing.compact) {
            Label {
                Text(label)
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
                    HStack(alignment: .firstTextBaseline, spacing: ThawSpacing.row) {
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
