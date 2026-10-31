//
//  AcknowledgementsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//  Floe changes © 2026 René Jiménez, under the same license.
//

import SwiftUI

// MARK: - AcknowledgementsStrings

/// The fixed text of the acknowledgements page. What it credits is in AcknowledgementsContent.
public nonisolated struct AcknowledgementsStrings: Sendable {
    public var credits: LocalizedStringResource
    public var origins: LocalizedStringResource
    public var licenses: LocalizedStringResource
    /// The menu the path's older stops fold into.
    public var older: LocalizedStringResource
    public var thanks: LocalizedStringResource
    public var contributors: LocalizedStringResource
    public var translators: LocalizedStringResource
    public var contribute: LocalizedStringResource
    public var helpTranslate: LocalizedStringResource

    public init(
        credits: LocalizedStringResource,
        origins: LocalizedStringResource,
        licenses: LocalizedStringResource,
        older: LocalizedStringResource,
        thanks: LocalizedStringResource,
        contributors: LocalizedStringResource,
        translators: LocalizedStringResource,
        contribute: LocalizedStringResource,
        helpTranslate: LocalizedStringResource
    ) {
        self.credits = credits
        self.origins = origins
        self.licenses = licenses
        self.older = older
        self.thanks = thanks
        self.contributors = contributors
        self.translators = translators
        self.contribute = contribute
        self.helpTranslate = helpTranslate
    }
}

// MARK: - AcknowledgementsContent

/// One project the page credits. Without a name, an origin is a paragraph and its link.
public struct AcknowledgementEntry {
    public var name: Text?
    public var detail: Text
    public var url: URL?

    public init(
        name: Text? = nil,
        detail: Text,
        url: URL? = nil
    ) {
        self.name = name
        self.detail = detail
        self.url = url
    }
}

/// What the licenses page shows.
public enum AcknowledgementLicenses {
    /// A bundled document, or the message to show when it could not be read.
    /// See AcknowledgementsDocument.
    case document(AttributedString?, unavailable: LocalizedStringResource)
    /// One entry per library, with a closing note.
    case libraries([AcknowledgementEntry], note: Text? = nil)
}

/// What the page credits and where its links go. A link without a URL does not show.
public struct AcknowledgementsContent {
    public var contributeURL: URL?
    public var translateURL: URL?
    public var contributorsURL: URL?
    public var translatorsURL: URL?
    public var originsIntro: Text?
    public var origins: [AcknowledgementEntry]
    public var licenses: AcknowledgementLicenses

    public init(
        contributeURL: URL?,
        translateURL: URL?,
        contributorsURL: URL?,
        translatorsURL: URL?,
        originsIntro: Text? = nil,
        origins: [AcknowledgementEntry],
        licenses: AcknowledgementLicenses
    ) {
        self.contributeURL = contributeURL
        self.translateURL = translateURL
        self.contributorsURL = contributorsURL
        self.translatorsURL = translatorsURL
        self.originsIntro = originsIntro
        self.origins = origins
        self.licenses = licenses
    }

    var showsLinkSeparator: Bool {
        contributeURL != nil && translateURL != nil
    }
}

// MARK: - AcknowledgementsDocument

/// Reads the notices a licenses page can show.
public nonisolated enum AcknowledgementsDocument {
    /// The RTF at a URL with its text and background colors stripped, so it follows the current
    /// appearance. Parsing is not free, so an app keeps the result in a static.
    public static func load(from url: URL?) -> AttributedString? {
        guard
            let url, let document = try? NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        else {
            return nil
        }
        let mutable = NSMutableAttributedString(attributedString: document)
        let whole = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.foregroundColor, range: whole)
        mutable.removeAttribute(.backgroundColor, range: whole)
        // The document's own fonts are the PDF's; on the page the reading scale takes over.
        mutable.removeAttribute(.font, range: whole)
        return try? AttributedString(mutable, including: \.appKit)
    }
}

// MARK: - AcknowledgementsPage

nonisolated enum AcknowledgementsPage: String, CaseIterable {
    case credits
    case origins
    case licenses

    init(selection: String?) {
        self = Self(rawValue: selection ?? "") ?? .credits
    }

    func title(in strings: AcknowledgementsStrings) -> LocalizedStringResource {
        switch self {
        case .credits: strings.credits
        case .origins: strings.origins
        case .licenses: strings.licenses
        }
    }
}

// MARK: - AcknowledgementsView

/// Credits and origins, followed by library notices, on a ReadingPage.
public struct AcknowledgementsView: View {
    @Environment(\.openURL) private var openURL

    private let appName: String
    private let strings: AcknowledgementsStrings
    private let content: AcknowledgementsContent

    @State private var selection: String?

    public init(
        appName: String,
        strings: AcknowledgementsStrings,
        content: AcknowledgementsContent
    ) {
        self.init(appName: appName, strings: strings, content: content, initialPage: .credits)
    }

    init(
        appName: String,
        strings: AcknowledgementsStrings,
        content: AcknowledgementsContent,
        initialPage: AcknowledgementsPage
    ) {
        self.appName = appName
        self.strings = strings
        self.content = content
        _selection = State(initialValue: initialPage.rawValue)
    }

    /// A link as the page prints it: the host and path, without the scheme.
    public static func displayText(for url: URL) -> String {
        (url.host() ?? "") + url.path()
    }

    var pathItems: [ReadingPathItem] {
        AcknowledgementsPage.allCases.map {
            ReadingPathItem(id: $0.rawValue, label: String(localized: $0.title(in: strings)))
        }
    }

    private var page: AcknowledgementsPage {
        AcknowledgementsPage(selection: selection)
    }

    public var body: some View {
        ReadingPage(
            appName: appName,
            path: pathItems,
            selection: $selection,
            title: Text(page.title(in: strings)),
            olderLabel: strings.older
        ) {
            switch page {
            case .credits:
                credits
            case .origins:
                origins
            case .licenses:
                licenses
            }
        } links: {
            if let url = content.contributeURL {
                Button(strings.contribute) {
                    openURL(url)
                }
                .buttonStyle(.settingsGlass)
            }
            if content.showsLinkSeparator {
                Text(verbatim: "/")
                    .foregroundStyle(ThawInk.supporting)
            }
            if let url = content.translateURL {
                Button(strings.helpTranslate) {
                    openURL(url)
                }
                .buttonStyle(.settingsGlass)
            }
        }
    }

    /// A thank-you and two links, with no names in the app. The lists live on the web.
    private var credits: some View {
        VStack(alignment: .leading, spacing: 22) {
            paragraph(Text(strings.thanks))

            VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                if let url = content.contributorsURL {
                    Link(destination: url) {
                        Text(strings.contributors).underline()
                    }
                }
                if let url = content.translatorsURL {
                    Link(destination: url) {
                        Text(strings.translators).underline()
                    }
                }
            }
            .font(ReadingPageType.body)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .id(AcknowledgementsPage.credits)
        .transition(.opacity)
    }

    private var origins: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let intro = content.originsIntro {
                paragraph(intro)
            }

            ForEach(Array(content.origins.enumerated()), id: \.offset) { _, origin in
                VStack(alignment: .leading, spacing: ThawSpacing.inset) {
                    if let name = origin.name {
                        name
                            .font(ReadingPageType.heading)
                            .accessibilityAddTraits(.isHeader)
                    }
                    paragraph(origin.detail)
                    if let url = origin.url {
                        Button {
                            openURL(url)
                        } label: {
                            Text(verbatim: Self.displayText(for: url))
                                .font(ReadingPageType.body)
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .id(AcknowledgementsPage.origins)
        .transition(.opacity)
    }

    private var licenses: some View {
        Group {
            switch content.licenses {
            case let .document(notices?, _):
                Text(notices)
                    .font(ReadingPageType.body)
                    .lineSpacing(ReadingPageType.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            case let .document(nil, unavailable):
                Text(unavailable)
                    .font(ReadingPageType.body)
                    .foregroundStyle(.secondary)
            case let .libraries(libraries, note):
                libraryList(libraries, note: note)
            }
        }
        .id(AcknowledgementsPage.licenses)
        .transition(.opacity)
    }

    private func libraryList(_ libraries: [AcknowledgementEntry], note: Text?) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(libraries.enumerated()), id: \.offset) { _, library in
                VStack(alignment: .leading, spacing: ThawSpacing.tight) {
                    if let name = library.name {
                        if let url = library.url {
                            Link(destination: url) {
                                name.underline()
                            }
                            .buttonStyle(.plain)
                        } else {
                            name
                        }
                    }
                    library.detail
                        .foregroundStyle(.secondary)
                }
                .font(ReadingPageType.body)
            }

            if let note {
                note
                    .font(ReadingPageType.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func paragraph(_ text: Text) -> some View {
        text
            .font(ReadingPageType.body)
            .lineSpacing(ReadingPageType.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}
