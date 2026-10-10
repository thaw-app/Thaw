//
//  ChangelogView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - ChangelogDocument

/// The release notes, fetched from the Thaw repository's changelog and parsed
/// just far enough to render: `## [version]` releases, `###` sections,
/// `####` themes, and `-` bullets with inline markdown.
///
/// Deliberately not a general markdown engine. The changelog follows Keep a
/// Changelog with a known shape; anything unrecognized degrades to plain
/// paragraph text rather than failing the panel. Content is not localized,
/// release notes ship as written, like the acknowledgements document.
struct ChangelogDocument {
    /// One block of release prose: plain text, or a GitHub alert.
    enum Block {
        case text(AttributedString)
        case callout(Callout)
    }

    /// A GitHub alert: `> [!WARNING]` and the `>` lines under it. Rendered as
    /// the design's one emphasis surface rather than as a plain quote.
    struct Callout {
        enum Kind: String, CaseIterable {
            case note, tip, important, warning, caution

            /// The kind a `> [!WARNING]` marker names, or `nil` for any other
            /// line.
            init?(marker line: String) {
                guard line.hasPrefix(">") else { return nil }
                let inner = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard inner.hasPrefix("[!"), inner.hasSuffix("]") else { return nil }
                guard let kind = Kind(rawValue: inner.dropFirst(2).dropLast().lowercased()) else {
                    return nil
                }
                self = kind
            }
        }

        /// A run of the alert's text: a paragraph, or one `- ` bullet.
        enum Part {
            case paragraph(AttributedString)
            case bullet(AttributedString)
        }

        var kind: Kind
        /// In the order written. A blank `>` line ends a paragraph, and each
        /// `- ` line is its own bullet, so a list inside an alert stays a list.
        var parts: [Part]
    }

    struct Release {
        var version: String
        /// The release day from a `## [version] - YYYY-MM-DD` heading, or
        /// `nil` when the heading carries none.
        var date: Date?
        /// The bold `**macOS 27 only · Build 108 · …**` line under the heading,
        /// shown beside the date rather than as the first paragraph.
        var facts: String?
        /// Prose paragraphs, alerts and intro bullets ahead of the first
        /// section.
        var intro: [Block] = []
        /// Image links ahead of the first section, rendered from bundled
        /// images so the page never fetches anything.
        var badges: [Badge] = []
        var sections: [Section] = []
    }

    /// An image link written as `[![alt](image.ext)](url)`. The image is a
    /// file in the app bundle, named by its file name.
    struct Badge: Equatable {
        var alt: String
        var imageFileName: String
        var url: URL
    }

    /// Reads the optional date after a release heading's closing bracket.
    /// Keep a Changelog writes it as ` - YYYY-MM-DD`; anything else after the
    /// bracket is ignored rather than failing the heading.
    ///
    /// Anchored at local midnight: UTC midnight renders a day early west of
    /// Greenwich.
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

    struct Section {
        var title: String
        var themes: [Theme] = []
    }

    /// A `####` theme inside a section; sections without themes get one
    /// unnamed theme holding their direct bullets.
    struct Theme {
        var title: String?
        var bullets: [Block] = []
    }

    var releases: [Release] = []

    /// The newest release that has content, skips an empty `[Unreleased]`.
    var newestRelease: Release? {
        releases.first { !$0.sections.isEmpty || !$0.intro.isEmpty }
    }

    /// Only the version-3 line is shown; 2.x notes ship with the 2.x app.
    private static let shownMajorVersion = 3

    /// The document's entries in the shown version line, in file order
    /// (newest first).
    static func displayReleases(in document: ChangelogDocument) -> [Release] {
        let prefix = "\(shownMajorVersion)."
        return document.releases.filter { release in
            release.version.hasPrefix(prefix) || release.version == String(shownMajorVersion)
        }
    }

    /// Where a loaded document came from, so the reader can say so.
    enum Source {
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

    /// Loads the changelog: from the repository when `allowFetch` is on,
    /// falling back to the last successful fetch. When the Privacy pane turns
    /// fetching off, only the cache is read.
    static func load(allowFetch: Bool) async -> (document: ChangelogDocument?, source: Source) {
        guard allowFetch else {
            return (cachedText().map(parse), .disabled)
        }
        if let text = await fetchedText() {
            saveCachedText(text)
            return (parse(text), .fetched)
        }
        if let text = cachedText() {
            return (parse(text), .cached)
        }
        return (nil, .unavailable)
    }

    private static func fetchedText() async -> String? {
        var request = URLRequest(url: Constants.changelogURL)
        request.timeoutInterval = 10
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200 ..< 300).contains(http.statusCode),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    /// The cached fetch lives in Caches: it is regenerable from the network
    /// and must not count against the user's backups.
    private static var cachedTextURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appending(path: "release-notes.md", directoryHint: .notDirectory)
    }

    private static func saveCachedText(_ text: String) {
        guard let url = cachedTextURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func cachedText() -> String? {
        guard let url = cachedTextURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The text of a release's opening facts line: the whole paragraph in
    /// bold, with its facts separated by ` · `. Anything else is prose.
    static func factsLine(_ paragraph: String) -> String? {
        let line = paragraph.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 else { return nil }
        let inner = String(line.dropFirst(2).dropLast(2))
        guard inner.contains(" · "), !inner.contains("**") else { return nil }
        return inner
    }

    /// `[![alt](image)](url)` on a line of its own.
    private static let badgePattern = /^\[!\[(?<alt>[^\]]*)\]\((?<image>[^)]+)\)\]\((?<url>[^)]+)\)$/

    static func parse(_ text: String) -> ChangelogDocument {
        var document = ChangelogDocument()
        var pendingBullet: String?
        var pendingParagraph: String?
        var pendingCallout: (kind: Callout.Kind, lines: [String])?

        func inline(_ markdown: String) -> AttributedString {
            (try? AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(markdown)
        }

        /// A block lands in the release intro ahead of the first section, and
        /// in the open theme after it, the same target a bullet takes.
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

        /// Prose ahead of a release's first section becomes an intro
        /// paragraph; prose anywhere else, including the file preamble, is
        /// dropped.
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

            // GitHub alerts: `> [!WARNING]` plus the `>` lines under it. A
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
            } else if line.isEmpty || line == "---" || line.hasPrefix("# ") {
                flushBullet()
            } else if pendingBullet != nil {
                // Continuation of a wrapped bullet.
                pendingBullet?.append(" " + line)
            } else if let match = line.wholeMatch(of: badgePattern) {
                flushParagraph()
                guard var release = document.releases.popLast() else { continue }
                if release.sections.isEmpty, let url = URL(string: String(match.url)) {
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

// MARK: - ChangelogView

// In-app release notes, presented as a sheet from the About pane, the
// sibling of AcknowledgementsView.
