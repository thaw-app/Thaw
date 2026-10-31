//
//  AcknowledgementsViewTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Acknowledgements", .serialized)
struct AcknowledgementsViewTests {
    private static let size = CGSize(width: 860, height: 780)
    private static let repository = URL(string: "https://example.com/repo")!

    private static let strings = AcknowledgementsStrings(
        credits: "Thanks page",
        origins: "Roots page",
        licenses: "Legal page",
        older: "Earlier",
        thanks: "Thank you all",
        contributors: "People",
        translators: "Linguists",
        contribute: "Join",
        helpTranslate: "Translate"
    )

    private static func content(
        repository: URL? = Self.repository,
        translate: URL? = Self.repository,
        licenses: AcknowledgementLicenses = .libraries([])
    ) -> AcknowledgementsContent {
        AcknowledgementsContent(
            contributeURL: repository,
            translateURL: translate,
            contributorsURL: repository,
            translatorsURL: repository,
            originsIntro: Text(verbatim: "Where it began"),
            origins: [AcknowledgementEntry(name: Text(verbatim: "Origin"), detail: Text(verbatim: "The start"), url: repository)],
            licenses: licenses
        )
    }

    private func view(
        page: AcknowledgementsPage = .credits,
        content: AcknowledgementsContent = Self.content()
    ) -> OffscreenRender<some View> {
        OffscreenRender(
            AcknowledgementsView(appName: "App", strings: Self.strings, content: content, initialPage: page)
                .frame(width: Self.size.width, height: Self.size.height),
            size: Self.size
        )
    }

    private func drawnPixels(_ render: OffscreenRender<some View>) async throws -> Data {
        await render.settle { (try? render.pixels())?.contains { $0 != 0 } == true }
        let pixels = try render.pixels()
        #expect(pixels.contains { $0 != 0 }, "the page draws something")
        return pixels
    }

    // MARK: Text

    @Test("The path and title use the words the app gives")
    func pageNames() {
        let view = AcknowledgementsView(appName: "App", strings: Self.strings, content: Self.content())
        #expect(view.pathItems.map(\.id) == ["credits", "origins", "licenses"])
        #expect(view.pathItems.map(\.label) == ["Thanks page", "Roots page", "Legal page"])
    }

    @Test("Each page names its own resource", arguments: [
        (AcknowledgementsPage.credits, "Thanks page"),
        (.origins, "Roots page"),
        (.licenses, "Legal page"),
    ])
    func pageTitle(page: AcknowledgementsPage, title: String) {
        #expect(String(localized: page.title(in: Self.strings)) == title)
    }

    @Test("A selection the page does not know falls back to credits", arguments: [nil, "unknown"])
    func unknownSelection(selection: String?) {
        #expect(AcknowledgementsPage(selection: selection) == .credits)
    }

    // MARK: Links

    @Test("Printed links show the host and path, without the scheme")
    func displayText() throws {
        let url = try #require(URL(string: "https://github.com/thaw-app/ThawUI"))
        #expect(AcknowledgementsView.displayText(for: url) == "github.com/thaw-app/ThawUI")
    }

    @Test("The slash between the two page links shows only when both exist", arguments: [
        (true, true, true),
        (true, false, false),
        (false, true, false),
        (false, false, false),
    ])
    func linkSeparator(hasRepository: Bool, hasTranslate: Bool, expected: Bool) {
        let content = Self.content(repository: hasRepository ? Self.repository : nil, translate: hasTranslate ? Self.repository : nil)
        #expect(content.showsLinkSeparator == expected)
    }

    // MARK: Drawing

    @Test("The same page draws the same pixels twice, so a difference below means something")
    func drawingIsRepeatable() async throws {
        #expect(try await drawnPixels(view(page: .origins)) == drawnPixels(view(page: .origins)))
    }

    @Test("Every page draws, and each draws differently")
    func pagesDraw() async throws {
        let credits = try await drawnPixels(view(page: .credits))
        let origins = try await drawnPixels(view(page: .origins))
        let licenses = try await drawnPixels(view(page: .licenses))
        #expect(credits != origins)
        #expect(origins != licenses)
    }

    @Test("A document draws its text, and a missing one draws the app's message")
    func documentPage() async throws {
        let loaded = view(page: .licenses, content: Self.content(licenses: .document(AttributedString("Notice text"), unavailable: "No notices")))
        let missing = view(page: .licenses, content: Self.content(licenses: .document(nil, unavailable: "No notices")))
        #expect(try await drawnPixels(loaded) != drawnPixels(missing))
    }

    @Test("A library list draws its entries and its note")
    func libraryPage() async throws {
        let entry = AcknowledgementEntry(name: Text(verbatim: "Sparkle"), detail: Text(verbatim: "MIT"), url: Self.repository)
        let plain = view(page: .licenses, content: Self.content(licenses: .libraries([entry])))
        let noted = view(page: .licenses, content: Self.content(licenses: .libraries([entry], note: Text(verbatim: "Marks belong to their owners"))))
        #expect(try await drawnPixels(plain) != drawnPixels(noted))
    }
}

@Suite("Acknowledgements document")
struct AcknowledgementsDocumentTests {
    private static func temporaryFile(containing text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).rtf")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test("No file means no document")
    func missing() {
        #expect(AcknowledgementsDocument.load(from: nil) == nil)
        #expect(AcknowledgementsDocument.load(from: URL(filePath: "/nonexistent/Acknowledgements.rtf")) == nil)
    }

    @Test("Loading keeps the text and drops the document's colors and fonts")
    func stripsColorsAndFonts() throws {
        let rtf = #"{\rtf1\ansi{\fonttbl{\f0 Times;}}{\colortbl;\red255\green0\blue0;\red0\green0\blue255;}\f0\fs48\cf1\cb2 Licensed under \ul MIT\ulnone .}"#
        let url = try Self.temporaryFile(containing: rtf)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(AcknowledgementsDocument.load(from: url))
        #expect(String(document.characters).contains("Licensed under MIT."))

        let loaded = try NSAttributedString(document, including: \.appKit)
        var keys = Set<NSAttributedString.Key>()
        loaded.enumerateAttributes(in: NSRange(location: 0, length: loaded.length)) { attributes, _, _ in
            keys.formUnion(attributes.keys)
        }
        #expect(keys.isDisjoint(with: [.foregroundColor, .backgroundColor, .font]))
        #expect(keys.contains(.underlineStyle), "underlines still show on the page")
    }
}
