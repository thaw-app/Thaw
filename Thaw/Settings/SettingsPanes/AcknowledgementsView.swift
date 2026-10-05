//
//  AcknowledgementsView.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import SwiftUI
import ThawUI

// MARK: - AcknowledgementsWindow

/// The standalone acknowledgements window, a ReadingPage like What's
/// New. A window rather than a sheet so it can carry the same glass and the
/// same path along the top.
struct AcknowledgementsWindow: Scene {
    @Bindable var appState: AppState

    var body: some Scene {
        ThawWindow(id: .acknowledgements, appState: appState) {
            AcknowledgementsView()
                .environment(appState)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 780)
        .windowStyle(.titleBar)
    }
}

// MARK: - AcknowledgementsView

/// Credits and origins, followed by library notices rendered from the
/// bundled Acknowledgements.rtf.
struct AcknowledgementsView: View {
    @Environment(\.openURL) private var openURL

    private enum Page: String, CaseIterable {
        case credits
        case origins
        case licenses

        var item: ReadingPathItem {
            switch self {
            case .credits: ReadingPathItem(id: rawValue, label: String(localized: "Credits"))
            case .origins: ReadingPathItem(id: rawValue, label: String(localized: "Origins"))
            case .licenses: ReadingPathItem(id: rawValue, label: String(localized: "Licenses"))
            }
        }
    }

    @State private var selection: String? = Page.credits.rawValue

    private static let originURL = URL(string: "https://github.com/jordanbaird/Ice")!
    private static let barometerURL = URL(string: "https://github.com/mackid1993/Barometer")!

    /// The bundled notices with document colors stripped, so the text follows
    /// the current appearance instead of shipping the RTF's black-on-white.
    private static let notices: AttributedString? = {
        guard
            let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "rtf"),
            let document = try? NSAttributedString(
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
        // The document's own fonts are the PDF's; on the page the reading
        // scale takes over, so only the emphasis runs keep their traits.
        mutable.removeAttribute(.font, range: whole)
        return try? AttributedString(mutable, including: \.appKit)
    }()

    private var page: Page {
        Page(rawValue: selection ?? "") ?? .credits
    }

    var body: some View {
        ReadingPage(
            path: Page.allCases.map(\.item),
            selection: $selection,
            title: title
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
            Button("Contribute") {
                openURL(Constants.repositoryURL)
            }
            .buttonStyle(.settingsGlass)
            Text(verbatim: "/")
                .foregroundStyle(ThawInk.supporting)
            Button("Help translate") {
                openURL(Constants.translateURL)
            }
            .buttonStyle(.settingsGlass)
        }
    }

    private var title: Text {
        switch page {
        case .credits: Text("Credits")
        case .origins: Text("Origins")
        case .licenses: Text("Licenses")
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 22) {
            ReadingParagraph("Thank you to everyone who contributes code, documentation, and translations to Thaw.")

            VStack(alignment: .leading, spacing: 12) {
                Link(destination: Constants.contributorsURL) {
                    Text("Contributors").underline()
                }
                Link(destination: Constants.translatorsURL) {
                    Text("Translators").underline()
                }
            }
            .font(ReadingPageType.body)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .id(Page.credits)
        .transition(.opacity)
    }

    private var origins: some View {
        VStack(alignment: .leading, spacing: 22) {
            ReadingParagraph("\(Constants.displayName) has its origins in Ice by Jordan Baird. Thank you for where it started.")
            Button {
                openURL(Self.originURL)
            } label: {
                Text(verbatim: "github.com/jordanbaird/Ice")
                    .font(ReadingPageType.body)
                    .underline()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            ReadingParagraph("Live system readings (CPU, Wi-Fi, battery) and the multi-item status bar publishing pattern are adapted from Barometer by mackid1993, licensed under the GNU GPLv3. Used with permission.")
            Button {
                openURL(Self.barometerURL)
            } label: {
                Text(verbatim: "github.com/mackid1993/Barometer")
                    .font(ReadingPageType.body)
                    .underline()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .id(Page.origins)
        .transition(.opacity)
    }

    private var licenses: some View {
        Group {
            if let notices = Self.notices {
                Text(notices)
                    .font(ReadingPageType.body)
                    .lineSpacing(ReadingPageType.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(Constants.displayName) couldn’t load the bundled acknowledgements document.")
                    .font(ReadingPageType.body)
                    .foregroundStyle(.secondary)
            }
        }
        .id(Page.licenses)
        .transition(.opacity)
    }
}
