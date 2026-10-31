//
//  ChangelogDocument.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI

// MARK: - ChangelogDocument

/// Keep a Changelog release notes, not localized: ## [version] releases, ### sections, #### themes, dash bullets,
/// numbered steps and inline markdown. Prose before a release's first section becomes a paragraph; the rest is dropped.
public nonisolated struct ChangelogDocument {
    /// One block of release prose: plain text, or a GitHub alert.
    public enum Block {
        case text(AttributedString)
        case callout(Callout)
    }

    /// A GitHub alert: a > [!WARNING] line and the > lines under it. Rendered as the design's one emphasis surface.
    public struct Callout {
        public enum Kind: String, CaseIterable, Sendable {
            case note, tip, important, warning, caution

            /// The kind a > [!WARNING] marker names, or nil for any other line.
            public init?(marker line: String) {
                guard line.hasPrefix(">") else { return nil }
                let inner = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard inner.hasPrefix("[!"), inner.hasSuffix("]"), let kind = Kind(rawValue: inner.dropFirst(2).dropLast().lowercased()) else {
                    return nil
                }
                self = kind
            }
        }

        /// A run of the alert's text: a paragraph or one dash bullet.
        public enum Part {
            case paragraph(AttributedString)
            case bullet(AttributedString)
        }

        public var kind: Kind
        /// In the order written. A blank > line ends a paragraph, and each dash line is its own bullet.
        public var parts: [Part]
    }

    public struct Release {
        public var version: String
        /// The release day from a ## [version] - YYYY-MM-DD heading, if it has one.
        public var date: Date?
        /// The bold line such as macOS 27 only · Build 108 · … under the heading,
        /// shown beside the date rather than as the first paragraph.
        public var facts: String?
        /// Prose paragraphs, alerts and intro bullets ahead of the first section.
        public var intro: [Block] = []
        /// Image links ahead of the first section, rendered from bundled
        /// images so the page never fetches anything.
        public var badges: [Badge] = []
        public var sections: [Section] = []
    }

    /// A Markdown link whose text is an image. The image is a file in the app bundle, named by its file name;
    /// the link is always https.
    public struct Badge: Equatable {
        public var alt: String
        public var imageFileName: String
        public var url: URL
    }

    /// Reads the optional dash and YYYY-MM-DD after a release heading's closing bracket, ignoring anything else there.
    /// Anchored at local midnight: UTC midnight renders a day early west of Greenwich.
    private static func releaseDate(in heading: String) -> Date? {
        guard let bracket = heading.firstIndex(of: "]") else {
            return nil
        }
        let trailer = heading[heading.index(after: bracket)...]
            .trimmingCharacters(in: .whitespaces)
        guard trailer.hasPrefix("-") else {
            return nil
        }
        let day = trailer.dropFirst().trimmingCharacters(in: .whitespaces).prefix(10)
        let localDay = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
        return try? Date(String(day), strategy: localDay)
    }

    public struct Section {
        public var title: String
        public var themes: [Theme] = []
    }

    /// A #### theme inside a section; sections without themes get one
    /// unnamed theme holding their direct bullets.
    public struct Theme {
        public var title: String?
        public var bullets: [Block] = []
    }

    public var releases: [Release] = []

    /// The newest release with content, skipping an empty [Unreleased].
    public var newestRelease: Release? {
        releases.first { !$0.sections.isEmpty || !$0.intro.isEmpty }
    }

    /// The document's entries in file order (newest first): those in the given version line, or with
    /// no line given, every one that has anything to read.
    public static func displayReleases(in document: ChangelogDocument, majorVersion: Int? = nil) -> [Release] {
        guard let majorVersion else {
            return document.releases.filter { !$0.sections.isEmpty || !$0.intro.isEmpty }
        }
        return document.releases.filter { release in
            release.version.hasPrefix("\(majorVersion).") || release.version == String(majorVersion)
        }
    }

    /// Where a loaded document came from, so the reader can say so.
    public enum Source {
        /// Fetched from the repository just now.
        case fetched
        /// The last successful fetch, because this one failed.
        case cached
        /// Fetching is switched off on the Privacy pane. The document, when
        /// there is one, is the last copy fetched while it was on.
        case disabled
        /// Nothing at all: fetching failed and there is no cache.
        case unavailable
    }

    /// Loads the changelog from the repository, falling back to the last successful fetch.
    /// With allowFetch off, as the Privacy pane can set it, only the cache is read.
    @concurrent
    public static func load(allowFetch: Bool, info: ThawAppInfo) async -> (document: ChangelogDocument?, source: Source) {
        await load(allowFetch: allowFetch, cacheFolder: info.cacheFolderName) {
            await fetchedText(from: info.changelogURL)
        }
    }

    /// The load itself, with the fetch supplied so a test needs no network.
    @concurrent
    static func load(
        allowFetch: Bool,
        cacheFolder: String?,
        fetch: @Sendable () async -> String?
    ) async -> (document: ChangelogDocument?, source: Source) {
        guard allowFetch else {
            return (cachedText(folder: cacheFolder).map(parse), .disabled)
        }
        // A response with no releases, like a captive portal's page, counts as
        // a failed fetch, so it never replaces the good copy.
        if let text = await fetch() {
            let document = parse(text)
            if !document.releases.isEmpty {
                saveCachedText(text, folder: cacheFolder)
                return (document, .fetched)
            }
        }
        if let text = cachedText(folder: cacheFolder) {
            return (parse(text), .cached)
        }
        return (nil, .unavailable)
    }

    private static func fetchedText(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard
            let (data, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode), let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    /// The cached fetch lives in Caches: it is regenerable from the network
    /// and must not count against the user's backups.
    static func cachedTextURL(folder: String?) -> URL? {
        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        let directory = folder.flatMap { caches?.appending(path: $0, directoryHint: .isDirectory) } ?? caches
        return directory?.appending(path: "release-notes.md", directoryHint: .notDirectory)
    }

    private static func saveCachedText(_ text: String, folder: String?) {
        guard let url = cachedTextURL(folder: folder) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func cachedText(folder: String?) -> String? {
        guard let url = cachedTextURL(folder: folder) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The text of a release's opening facts line: the whole paragraph in
    /// bold, with its facts separated by a middle dot with a space on each side. Anything else is prose.
    public static func factsLine(_ paragraph: String) -> String? {
        let line = paragraph.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 else { return nil }
        let inner = String(line.dropFirst(2).dropLast(2))
        guard inner.contains(" · "), !inner.contains("**") else { return nil }
        return inner
    }

    /// A Markdown link whose text is an image, on a line of its own.
    private static nonisolated(unsafe) let badgePattern = /^\[!\[(?<alt>[^\]]*)\]\((?<image>[^)]+)\)\]\((?<url>[^)]+)\)$/

    /// A badge's link when it is https. The file is fetched and a click hands the link to openURL,
    /// so any other scheme could open a local file or launch another app.
    private static func badgeURL(_ string: String) -> URL? {
        guard
            let url = URL(string: string), url.scheme?.lowercased() == "https", url.host() != nil
        else {
            return nil
        }
        return url
    }

    public static func parse(_ text: String) -> ChangelogDocument {
        var document = ChangelogDocument()
        var pendingBullet: String?
        var pendingParagraph: String?
        var pendingCallout: (kind: Callout.Kind, lines: [String])?

        // The notes come over the network, so a link in them opens only over https.
        func inline(_ markdown: String) -> AttributedString {
            var text = (try? AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(markdown)
            for run in text.runs where run.link?.scheme?.lowercased() != "https" {
                text[run.range].link = nil
            }
            return text
        }

        // A block lands in the release intro ahead of the first section, and
        // in the open theme after it, the same target a bullet takes.
        func appendBlock(_ block: Block) {
            guard !document.releases.isEmpty else { return }
            var release = document.releases.removeLast()
            if release.sections.isEmpty {
                release.intro.append(block)
            } else {
                var section = release.sections.removeLast()
                if section.themes.isEmpty {
                    section.themes.append(Theme(title: nil))
                }
                var theme = section.themes.removeLast()
                theme.bullets.append(block)
                section.themes.append(theme)
                release.sections.append(section)
            }
            document.releases.append(release)
        }

        // Prose ahead of a release's first section becomes an intro paragraph; prose anywhere else,
        // including the file preamble, is dropped.
        func flushParagraph() {
            guard let paragraph = pendingParagraph else { return }
            pendingParagraph = nil
            guard !document.releases.isEmpty else { return }
            var release = document.releases.removeLast()
            if release.sections.isEmpty {
                if release.intro.isEmpty, release.facts == nil, let facts = Self.factsLine(paragraph) {
                    release.facts = facts
                } else {
                    release.intro.append(.text(inline(paragraph)))
                }
            }
            document.releases.append(release)
        }

        func flushCallout() {
            guard let callout = pendingCallout else { return }
            pendingCallout = nil
            var parts: [Callout.Part] = []
            var paragraph: [String] = []
            func endParagraph() {
                guard !paragraph.isEmpty else { return }
                parts.append(.paragraph(inline(paragraph.joined(separator: " "))))
                paragraph = []
            }
            for line in callout.lines {
                if line.isEmpty {
                    endParagraph()
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    endParagraph()
                    parts.append(.bullet(inline(String(line.dropFirst(2)))))
                } else if line.hasPrefix("**"), line.hasSuffix("**"), !paragraph.isEmpty {
                    // A bold line of its own leads what follows, like the
                    // "What's new" and "What's fixed" lines in a summary.
                    endParagraph()
                    paragraph.append(line)
                } else {
                    paragraph.append(line)
                }
            }
            endParagraph()
            guard !parts.isEmpty else { return }
            appendBlock(.callout(Callout(kind: callout.kind, parts: parts)))
        }

        func flushBullet() {
            flushParagraph()
            flushCallout()
            guard let bullet = pendingBullet else { return }
            pendingBullet = nil
            appendBlock(.text(inline(bullet)))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // GitHub alerts: > [!WARNING] plus the > lines under it. A
            // plain blockquote keeps falling through to paragraph text below.
            if let kind = Callout.Kind(marker: line) {
                flushBullet()
                pendingCallout = (kind, [])
                continue
            }
            if line.hasPrefix(">") {
                if pendingCallout != nil {
                    // Blank lines are kept: they are where the paragraphs break.
                    let content = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                    pendingCallout?.lines.append(content)
                    continue
                }
            } else {
                flushCallout()
            }

            if line.hasPrefix("## [") {
                flushBullet()
                let version = line.dropFirst(4).prefix { $0 != "]" }
                document.releases.append(Release(version: String(version), date: releaseDate(in: line)))
            } else if line.hasPrefix("#### ") {
                flushBullet()
                guard var release = document.releases.popLast() else { continue }
                // A theme with no open section is dropped, and the release is
                // re-appended so it is not lost.
                guard var section = release.sections.popLast() else {
                    document.releases.append(release)
                    continue
                }
                section.themes.append(Theme(title: String(line.dropFirst(5))))
                release.sections.append(section)
                document.releases.append(release)
            } else if line.hasPrefix("### ") {
                flushBullet()
                guard var release = document.releases.popLast() else { continue }
                release.sections.append(Section(title: String(line.dropFirst(4))))
                document.releases.append(release)
            } else if line.hasPrefix("- ") {
                flushBullet()
                pendingBullet = String(line.dropFirst(2))
            } else if line.wholeMatch(of: /\d+\. .+/) != nil {
                // A numbered step keeps its number and stays on its own line.
                flushBullet()
                pendingBullet = line
            } else if line.isEmpty || line == "---" || line.hasPrefix("# ") {
                flushBullet()
            } else if pendingBullet != nil {
                // Continuation of a wrapped bullet.
                pendingBullet?.append(" " + line)
            } else if let match = line.wholeMatch(of: badgePattern) {
                flushParagraph()
                guard var release = document.releases.popLast() else { continue }
                if release.sections.isEmpty, let url = badgeURL(String(match.url)) {
                    release.badges.append(Badge(
                        alt: String(match.alt),
                        imageFileName: String(match.image),
                        url: url
                    ))
                }
                document.releases.append(release)
            } else if line.hasPrefix("<") {
                // The panel has no renderer for raw HTML.
                flushParagraph()
            } else if pendingParagraph != nil {
                pendingParagraph?.append(" " + line)
            } else {
                pendingParagraph = line
            }
        }
        flushBullet()
        return document
    }
}
