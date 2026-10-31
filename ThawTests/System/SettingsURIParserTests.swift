//
//  SettingsURIParserTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// How thaw:// URLs become requests, and which of them wait for an approved sender.
@Suite("Settings URI parser")
struct SettingsURIParserTests {
    private func parse(_ string: String) throws -> SettingsURIRequest {
        try SettingsURIParser.parse(#require(URL(string: string)))
    }

    private func route(_ string: String) throws -> SettingsURIRoute {
        try parse(string).route
    }

    // MARK: - Settings routes

    @Test("set reads key, value and display")
    func setParses() throws {
        #expect(try route("thaw://set?key=autoRehide&value=true") == .set(key: "autoRehide", value: "true", displayUUID: nil))
        #expect(try route("thaw://set?key=k&value=v&display=D") == .set(key: "k", value: "v", displayUUID: "D"))
    }

    @Test("set keeps empty values, which the handler rejects by key")
    func setKeepsEmptyValues() throws {
        #expect(try route("thaw://set?key=&value=") == .set(key: "", value: "", displayUUID: nil))
    }

    @Test("set without key or value is malformed", arguments: ["thaw://set", "thaw://set?key=k", "thaw://set?value=v", "thaw://set?key"])
    func setMissingParameters(string: String) throws {
        #expect(try route(string) == .malformed(host: "set"))
    }

    @Test("toggle reads key and display, and needs a key")
    func toggleParses() throws {
        #expect(try route("thaw://toggle?key=showOnHover") == .toggle(key: "showOnHover", displayUUID: nil))
        #expect(try route("thaw://toggle?key=k&display=D") == .toggle(key: "k", displayUUID: "D"))
        #expect(try route("thaw://toggle?display=D") == .malformed(host: "toggle"))
    }

    @Test("get passes every parameter through and needs none")
    func getParses() throws {
        let full = try route("thaw://get?key=all&display=D&callback=app://r&broadcast=true&requestId=7")
        #expect(full == .get(SettingsURIGetQuery(key: "all", displayUUID: "D", callback: "app://r", broadcast: true, requestId: "7")))
        let bare = try route("thaw://get")
        #expect(bare == .get(SettingsURIGetQuery(key: nil, displayUUID: nil, callback: nil, broadcast: false, requestId: nil)))
        let notTrue = try route("thaw://get?broadcast=yes")
        #expect(notTrue == .get(SettingsURIGetQuery(key: nil, displayUUID: nil, callback: nil, broadcast: false, requestId: nil)))
    }

    @Test("The first value of a repeated parameter wins")
    func firstValueWins() throws {
        #expect(try route("thaw://toggle?key=a&key=b") == .toggle(key: "a", displayUUID: nil))
    }

    @Test("Only get with key version is the version read")
    func versionRead() throws {
        #expect(try parse("thaw://get?key=version").isVersionRead)
        #expect(try parse("thaw://get?key=version&callback=app://r").isVersionRead)
        #expect(try !parse("thaw://get?key=Version").isVersionRead)
        #expect(try !parse("thaw://get?key=all").isVersionRead)
        #expect(try !parse("thaw://get").isVersionRead)
        #expect(try !parse("thaw://set?key=version&value=1").isVersionRead)
        #expect(try !parse("thaw://toggle-hidden?key=version").isVersionRead)
    }

    @Test("authorize and toggle-thawbar take no parameters")
    func parameterlessGatedRoutes() throws {
        #expect(try route("thaw://authorize") == .authorize)
        #expect(try route("thaw://authorize?key=x") == .authorize)
        #expect(try route("thaw://toggle-thawbar") == .toggleThawBar)
    }

    // MARK: - Item routes

    @Test("reveal-item passes bundle and item-id through for the handler to check")
    func revealItemParses() throws {
        #expect(try route("thaw://reveal-item?bundle=com.a") == .revealItem(bundle: "com.a", itemID: nil, hold: false))
        #expect(try route("thaw://reveal-item?item-id=com.a:x") == .revealItem(bundle: nil, itemID: "com.a:x", hold: false))
        #expect(try route("thaw://reveal-item") == .revealItem(bundle: nil, itemID: nil, hold: false))
    }

    @Test("reveal-item holds only when hold is exactly true")
    func revealItemHold() throws {
        #expect(try route("thaw://reveal-item?bundle=com.a&hold=true") == .revealItem(bundle: "com.a", itemID: nil, hold: true))
        #expect(try route("thaw://reveal-item?bundle=com.a&hold=1") == .revealItem(bundle: "com.a", itemID: nil, hold: false))
    }

    @Test("release-item passes bundle and item-id through and needs authorization")
    func releaseItemParses() throws {
        #expect(try route("thaw://release-item?bundle=com.a") == .releaseItem(bundle: "com.a", itemID: nil))
        #expect(try route("thaw://release-item?item-id=com.a:x") == .releaseItem(bundle: nil, itemID: "com.a:x"))
        #expect(SettingsURIParser.parse(try #require(URL(string: "thaw://release-item?bundle=com.a"))).requiresAuthorization)
    }

    @Test("proxy-press needs a non-empty bundle")
    func proxyPressParses() throws {
        #expect(try route("thaw://proxy-press?bundle=com.a") == .proxyPress(bundle: "com.a"))
        #expect(try route("thaw://proxy-press?bundle=") == .malformed(host: "proxy-press"))
        #expect(try route("thaw://proxy-press") == .malformed(host: "proxy-press"))
    }

    @Test("dump-items keeps the callback as given")
    func dumpItemsParses() throws {
        #expect(try route("thaw://dump-items") == .dumpItems(callback: nil))
        #expect(try route("thaw://dump-items?callback=app://dump") == .dumpItems(callback: "app://dump"))
        #expect(try route("thaw://dump-items?callback=") == .dumpItems(callback: ""))
    }

    @Test("Launcher operations read their identifier and response parameters, ignoring empty values")
    func launcherParses() throws {
        let activate = try route("thaw://activate-item?item-id=x&callback=app://r&requestId=1")
        let expected = SettingsURILauncherQuery(identifier: "x", callback: "app://r", broadcast: false, requestId: "1", move: nil)
        #expect(activate == .launcher(.activateItem, expected))

        let empty = try route("thaw://apply-profile?profile-id=&callback=&requestId=&broadcast=true")
        let emptyExpected = SettingsURILauncherQuery(identifier: nil, callback: nil, broadcast: true, requestId: nil, move: nil)
        #expect(empty == .launcher(.applyProfile, emptyExpected))

        let listing = try route("thaw://list-items?item-id=x")
        let listingExpected = SettingsURILauncherQuery(identifier: nil, callback: nil, broadcast: false, requestId: nil, move: nil)
        #expect(listing == .launcher(.listItems, listingExpected))
    }

    @Test("move-item carries every item-id, the section and the anchor")
    func moveItemParses() throws {
        let parsed = try route("thaw://move-item?item-id=a&item-id=&item-id=b&section=hidden&after-id=")
        let move = SettingsURIMoveQuery(itemIDs: ["a", "b"], section: "hidden", afterID: nil)
        let expected = SettingsURILauncherQuery(identifier: "a", callback: nil, broadcast: false, requestId: nil, move: move)
        #expect(parsed == .launcher(.moveItem, expected))

        let anchored = try route("thaw://move-item?item-id=a&after-id=c")
        guard case let .launcher(_, query) = anchored else {
            Issue.record("move-item did not parse as a launcher operation")
            return
        }
        #expect(query.move == SettingsURIMoveQuery(itemIDs: ["a"], section: "", afterID: "c"))
    }

    // MARK: - Actions and unknown hosts

    @Test("Each action is recognized by its host, in any case", arguments: SettingsURIAction.allCases)
    func actionsParse(action: SettingsURIAction) throws {
        #expect(try route("thaw://\(action.rawValue)") == .action(action))
        #expect(try route("thaw://\(action.rawValue.uppercased())?key=x") == .action(action))
    }

    @Test("A host Thaw does not know is unrecognized", arguments: ["thaw://", "thaw://unknown", "thaw://settings", "thaw://toggle-thaw-bar"])
    func unknownHosts(string: String) throws {
        let request = try parse(string)
        #expect(request.route == .unrecognized(host: URL(string: string)?.host?.lowercased() ?? ""))
    }

    @Test("Parsing the same URL twice gives the same request")
    func parsingIsDeterministic() throws {
        let string = "thaw://move-item?item-id=a&section=visible&requestId=3"
        #expect(try parse(string) == parse(string))
    }

    // MARK: - Authorization

    @Test("Routes that change settings, drive items or export data need an approved sender", arguments: [
        "thaw://set?key=k&value=v", "thaw://toggle?key=k", "thaw://get?key=all", "thaw://get?key=version",
        "thaw://authorize", "thaw://reveal-item?bundle=b", "thaw://proxy-press?bundle=b", "thaw://PROXY-PRESS?bundle=b",
        "thaw://toggle-thawbar", "thaw://dump-items", "thaw://list-items", "thaw://activate-item?item-id=x",
        "thaw://list-profiles", "thaw://apply-profile?profile-id=p", "thaw://get-appearance",
        "thaw://move-item?item-id=a&section=hidden", "thaw://set", "thaw://toggle", "thaw://proxy-press",
    ])
    func gatedRoutesNeedApproval(string: String) throws {
        #expect(try parse(string).requiresAuthorization)
    }

    @Test("Every launcher operation is gated", arguments: LauncherURIOperation.allCases)
    func launcherOperationsAreGated(operation: LauncherURIOperation) throws {
        #expect(try parse("thaw://\(operation.rawValue)").requiresAuthorization)
    }

    @Test("Actions a hotkey can also run stay open to any sender", arguments: SettingsURIAction.allCases)
    func actionsStayOpen(action: SettingsURIAction) throws {
        #expect(try !parse("thaw://\(action.rawValue)").requiresAuthorization)
    }

    @Test("Unrecognized hosts need no approval, since nothing runs", arguments: ["thaw://", "thaw://unknown"])
    func unrecognizedStaysOpen(string: String) throws {
        #expect(try !parse(string).requiresAuthorization)
    }

    @Test("Each action maps to the hotkey that does the same thing")
    func actionsMapToHotkeys() {
        #expect(SettingsURIAction.toggleHidden.hotkeyAction == .toggleHiddenSection)
        #expect(SettingsURIAction.toggleAlwaysHidden.hotkeyAction == .toggleAlwaysHiddenSection)
        #expect(SettingsURIAction.toggleSwap.hotkeyAction == .toggleSwap)
        #expect(SettingsURIAction.search.hotkeyAction == .searchMenuBarItems)
        #expect(SettingsURIAction.toggleApplicationMenus.hotkeyAction == .toggleApplicationMenus)
        #expect(SettingsURIAction.toggleZenMode.hotkeyAction == .toggleZenMode)
        #expect(SettingsURIAction.toggleLayoutEditor.hotkeyAction == .toggleLayoutEditor)
        #expect(SettingsURIAction.openSettings.hotkeyAction == nil)
        #expect(SettingsURIAction.itemHints.hotkeyAction == nil)
    }
}
