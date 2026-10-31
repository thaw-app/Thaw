//
//  AboutSettingsPaneTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import AppKit
import Foundation
import Observation
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Observable
private final class FakeUpdates: AboutUpdatesModel {
    var updateChannel = UpdateChannel.beta
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var canCheckNow = true
    var lastUpdateCheckDate: Date?
    var checks = 0

    func checkForUpdates() {
        checks += 1
    }
}

@MainActor
@Suite("About page", .serialized)
struct AboutSettingsPaneTests {
    private static let size = CGSize(width: 760, height: 900)
    private static let url = URL(string: "https://example.com")!

    private static let strings = AboutStrings(
        tagline: "A tagline",
        versionLabel: { "Version \($0) build \($1) commit \($2)" },
        copied: "Done",
        copyHelp: "Copy for a report",
        copyLabel: "Copy",
        whatsNew: "News",
        reportBug: "Bug",
        more: "More",
        sourceCode: "Code",
        credits: "Thanks",
        support: "Give"
    )

    private static let updateStrings = AboutUpdateStrings(
        updateChannel: "Channel",
        automaticUpdates: "Automatic",
        checkNow: "Check",
        notChecked: "Never",
        lastChecked: { "Checked \($0)" },
        channelName: { LocalizedStringResource(stringLiteral: $0.rawValue) },
        automaticUpdatesName: { $0 == .off ? "Full off" : "Full on" },
        automaticUpdatesShortName: { $0 == .off ? "Off" : "On" }
    )

    private static let version = AboutVersionDetails(version: "3.0", build: "42", commit: "abc123", report: "App 3.0 (42)\nCommit: abc123")

    private func pane(
        links: AboutLinks = AboutLinks(sourceCode: url, reportBug: url, support: url),
        moreMenu: [[AboutMenuItem]] = [],
        updates: AboutUpdateControls? = nil
    ) -> OffscreenRender<some View> {
        OffscreenRender(
            AboutSettingsPane(
                appName: "App",
                version: Self.version,
                links: links,
                moreMenu: moreMenu,
                updates: updates,
                copyright: Text(verbatim: "Copyright"),
                strings: Self.strings,
                showWhatsNew: {},
                showCredits: {}
            )
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

    private func controls(_ model: FakeUpdates, channels: [UpdateChannel] = UpdateChannel.selectable) -> AboutUpdateControls {
        AboutUpdateControls(model: model, channels: channels, strings: Self.updateStrings)
    }

    @Test("The same page draws the same pixels twice, so a difference below means something")
    func drawingIsRepeatable() async throws {
        #expect(try await drawnPixels(pane()) == drawnPixels(pane()))
    }

    // MARK: Details

    @Test("The version line reads version, build and commit")
    func versionLine() {
        #expect(Self.version.line == "3.0 (42) · abc123")
    }

    @Test("VoiceOver's version label is the app's")
    func versionLabel() {
        #expect(String(localized: Self.strings.versionLabel("3.0", "42", "abc")) == "Version 3.0 build 42 commit abc")
    }

    @Test("Copying replaces what the pasteboard held with the report")
    func copyReplacesPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        AboutSettingsPane.copy(Self.version.report, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == Self.version.report)
    }

    // MARK: Updates

    @Test("No check yet says so, and a check names its date")
    func footnote() {
        #expect(Self.updateStrings.footnote(lastCheck: nil) == "Never")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        #expect(String(localized: Self.updateStrings.footnote(lastCheck: date)) == "Checked \(formatted)")
    }

    @Test("The channel binding reads and writes the updater")
    func channelBinding() {
        let model = FakeUpdates()
        let controls = controls(model)
        #expect(controls.channel.wrappedValue == .beta)
        controls.channel.wrappedValue = .alpha
        #expect(model.updateChannel == .alpha)
    }

    @Test("The automatic updates binding writes both of the updater's switches", arguments: AutomaticUpdates.allCases)
    func automaticBinding(choice: AutomaticUpdates) {
        let model = FakeUpdates()
        let controls = controls(model)
        controls.automaticUpdates.wrappedValue = choice
        #expect(model.automaticallyChecksForUpdates == choice.checks)
        #expect(model.automaticallyDownloadsUpdates == choice.downloads)
        #expect(controls.automaticUpdates.wrappedValue == choice)
    }

    @Test("Without an updater there is no updates card")
    func cardIsOptional() async throws {
        let without = try await drawnPixels(pane())
        let with = try await drawnPixels(pane(updates: controls(FakeUpdates())))
        #expect(without != with)
    }

    @Test("The card follows the updater while it is on screen")
    func cardFollowsModel() async throws {
        let model = FakeUpdates()
        let render = pane(updates: controls(model))
        let before = try await drawnPixels(render)
        model.lastUpdateCheckDate = Date(timeIntervalSince1970: 1_700_000_000)
        await render.settle { (try? render.pixels()) != before }
        #expect(try render.pixels() != before)
    }

    @Test("The channels on offer are the app's")
    func channelsDiffer() async throws {
        let model = FakeUpdates()
        let two = try await drawnPixels(pane(updates: controls(model, channels: [.stable, .beta])))
        let one = try await drawnPixels(pane(updates: controls(model, channels: [.beta])))
        #expect(two != one)
    }

    // MARK: Links

    @Test("A link without a URL does not show")
    func missingLinks() async throws {
        let all = try await drawnPixels(pane())
        let none = try await drawnPixels(pane(links: AboutLinks(sourceCode: nil, reportBug: nil, support: nil)))
        #expect(all != none)
    }

    @Test("With no items the actions button does not show")
    func moreButtonIsOptional() async throws {
        let empty = try await drawnPixels(pane(moreMenu: [[]]))
        let item = AboutMenuItem("Item", systemImage: "star") {}
        let filled = try await drawnPixels(pane(moreMenu: [[item]]))
        #expect(empty != filled)
    }

    // MARK: Menu

    @Test("Groups are separated, and an empty group leaves no separator")
    func menuGroups() {
        let first = AboutMenuItem("One", systemImage: "star") {}
        let second = AboutMenuItem("Two", systemImage: "globe", url: Self.url)
        let menu = AboutMoreMenu.make(groups: [[], [first], [], [second]]) { _ in }
        #expect(menu.items.map(\.title) == ["One", "", "Two"])
        #expect(menu.items.map(\.isSeparatorItem) == [false, true, false])
        #expect(menu.items[0].image != nil)
    }

    @Test("An item with a URL opens it, and an item with an action runs it")
    func menuActions() {
        var opened: [URL] = []
        var ran = 0
        let menu = AboutMoreMenu.make(groups: [
            [
                AboutMenuItem("Link", systemImage: "globe", url: Self.url),
                AboutMenuItem("Run", systemImage: "star") { ran += 1 },
            ],
        ]) { opened.append($0) }
        menu.performActionForItem(at: 0)
        menu.performActionForItem(at: 1)
        #expect(opened == [Self.url])
        #expect(ran == 1)
    }
}
