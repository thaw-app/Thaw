//
//  SuppliedStringsTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Thaw
//  Licensed under the GNU GPLv3

import Foundation
import SwiftUI
import Testing
@testable import ThawUI

@MainActor
@Suite("Supplied strings")
struct SuppliedStringsTests {
    private static let whatsNew = WhatsNewStrings(
        title: "App news",
        releaseTitle: { "News in \($0)" },
        releaseSubtitle: { date, facts in Text("\(date) with \(facts)") },
        noRelease: { channel, appName in Text("No \(channel) for \(appName)") },
        loadFailed: { "\($0) failed" },
        fetchingOff: "Fetching off",
        fetchingOffCached: "Fetching off, cached",
        updateReady: "Ready",
        cachedCopy: "Cached",
        fullChangelog: "All notes",
        older: "Earlier",
        channelName: { LocalizedStringResource(stringLiteral: $0 == .beta ? "Testing" : "Other") },
        calloutName: { LocalizedStringResource(stringLiteral: $0 == .tip ? "Hint" : "Other") }
    )

    private static let info = ThawAppInfo(
        displayName: "App",
        version: "3.0.0",
        changelogURL: URL(filePath: "/changelog"),
        releasesURL: URL(filePath: "/releases")
    )

    @Test("What's New shows the text it is given")
    func whatsNew() {
        let view = WhatsNewView(info: Self.info, strings: Self.whatsNew)
        #expect(view.strings.fullChangelog == "All notes")
        #expect(view.strings.fetchingOff == "Fetching off")
        #expect(view.strings.fetchingOffCached == "Fetching off, cached")
        #expect(String(localized: view.strings.releaseTitle("3.1")) == "News in 3.1")
        #expect(String(localized: view.strings.loadFailed("App")) == "App failed")
        #expect(String(localized: view.strings.channelName(.beta)) == "Testing")
        #expect(String(localized: view.strings.calloutName(.tip)) == "Hint")
    }

    @Test("A resource keeps the catalog key the old string key used")
    func interpolatedKeys() {
        let title: LocalizedStringResource = "What’s new in \("3.1")"
        #expect(title.key == "What’s new in %@")
        let zoom: LocalizedStringResource = "Zoom: \(125)%"
        #expect(zoom.key == "Zoom: %lld%%")
        #expect(String(localized: zoom) == "Zoom: 125%")
    }

    @Test("A resource keeps the bundle the app gave it")
    func bundleSurvives() {
        let bundle = LocalizedStringResource.BundleDescription.atURL(URL(filePath: "/App.bundle"))
        let title = LocalizedStringResource("Name", bundle: bundle)
        let segment = ThawSegment(1, title: title)
        #expect(segment.title == title)
        #expect(segment.title != "Name")
    }

    @Test("The reading page takes the name of its overflow menu")
    func readingPage() {
        let page = ReadingPage(appName: "App", path: [], selection: .constant(nil), title: Text(verbatim: "T"), olderLabel: "Earlier") {
            EmptyView()
        } links: {
            EmptyView()
        }
        #expect(page.olderLabel == "Earlier")
    }

    @Test("Single labels are the ones supplied")
    func singleLabels() {
        #expect(SettingsFilterField(prompt: "Find", clearLabel: "Wipe", text: .constant("")).clearLabel == "Wipe")
        #expect(ThawCheckboxToggleStyle(onValue: "Yes", offValue: "No").onValue == "Yes")
        #expect(ThawCheckboxToggleStyle(onValue: "Yes", offValue: "No").offValue == "No")
        #expect(ThawFirstRunHint(systemImage: "star", "Text", dismissLabel: "Later") {}.dismissLabel == "Later")
        #expect(ThawHintTipViewStyle(dismissLabel: "Later").dismissLabel == "Later")
        let items = Binding<[SectionedListItem<Int, EmptyView>]>.constant([])
        #expect(SectionedList(selection: .constant(nil), items: items, openLabel: "Launch").openLabel == "Launch")
    }

    @Test("An alpha or beta badge shows the word it is given")
    func badges() {
        #expect(ThawBadge.alpha("Early").title == "Early")
        #expect(ThawBadge.beta("Soon").title == "Soon")
    }

    @Test("Zoom commands and controls hold the app's words")
    func zoom() {
        let strings = AppUIZoomStrings(zoomIn: "Bigger", zoomOut: "Smaller", actualSize: "Reset", level: { "\($0) percent" })
        #expect(AppUIZoomControls(strings: strings).strings.zoomIn == "Bigger")
        #expect(AppUIZoomCommands(strings: strings).strings.actualSize == "Reset")
        #expect(String(localized: strings.level(125)) == "125 percent")
    }

    @Test("The gradient picker holds the app's words")
    func gradientPicker() {
        let strings = ThawGradientPickerStrings(addStop: "Add", spaceStopsEvenly: "Spread", stopName: { "Stop \($0)" })
        let picker = ThawGradientPicker("Fill", gradient: .constant(ThawGradient()), strings: strings)
        #expect(picker.strings.addStop == "Add")
        #expect(String(localized: picker.strings.stopName(2)) == "Stop 2")
    }

    @Test("The no-matches state gives the app the trimmed query")
    func noMatches() {
        let state = NoMatchesState(query: "  thaw ", title: { "Nothing for \($0)" }, caption: "Try again")
        #expect(String(localized: state.resolvedTitle) == "Nothing for thaw")
        #expect(state.caption == "Try again")
    }

    @Test("The no-matches state has a title of its own for an empty query")
    func noMatchesEmptyQuery() {
        func state(_ query: String) -> NoMatchesState {
            NoMatchesState(query: query, title: { "Nothing for \($0)" }, emptyQueryTitle: "Nothing found", caption: "Try again")
        }
        #expect(state("   ").resolvedTitle == "Nothing found")
        #expect(String(localized: state(" thaw ").resolvedTitle) == "Nothing for thaw")
    }

    @Test("The privacy notice shows the promise it is given")
    func privacyNotice() {
        let notice = SettingsPrivacyNotice(title: "Promise", message: "Kept")
        #expect(notice.title == "Promise")
        #expect(notice.message == "Kept")
    }

    @Test("Persisted option values stay the same")
    func rawValues() {
        #expect(SearchFieldBeam.allCases.map(\.rawValue) == ["off", "colorful", "mono", "ocean", "sunset"])
        #expect(SearchFieldShape.allCases.map(\.rawValue) == ["rounded", "capsule", "square"])
        #expect(UpdateChannel.allCases.map(\.rawValue) == ["stable", "beta", "alpha"])
        #expect(ThawHUDPlacement.allCases.map(\.rawValue) == ["leading", "center", "trailing"])
    }
}
