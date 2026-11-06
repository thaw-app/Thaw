//
//  HomebrewTapNoticeTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

@Suite("Homebrew tap notice")
struct HomebrewTapNoticeTests {
    @Test("Betas and release candidates follow thaw@2-beta, releases thaw@2")
    func caskFollowsTheBuild() {
        #expect(HomebrewTapNotice.tapCask(forAppVersion: "2.2.0-beta.2") == "thaw@2-beta")
        #expect(HomebrewTapNotice.tapCask(forAppVersion: "2.2.0-rc.1") == "thaw@2-beta")
        #expect(HomebrewTapNotice.tapCask(forAppVersion: "2.2.0") == "thaw@2")
        #expect(HomebrewTapNotice.tapCask(forAppVersion: "2.2.0-1") == "thaw@2")
    }

    @Test("Commands uninstall the main-repository cask before installing from the tap")
    func commandsUninstallFirst() {
        let commands = HomebrewTapNotice.commands(appVersion: "2.2.0", installedCasks: ["thaw"])
        #expect(commands == [
            "brew uninstall --cask thaw",
            "brew tap thaw-app/tap",
            "brew trust --cask thaw-app/tap/thaw@2",
            "brew install --cask thaw-app/tap/thaw@2",
        ])
    }

    @Test("Without a Homebrew install the commands start at the tap")
    func commandsWithoutHomebrew() {
        let commands = HomebrewTapNotice.commands(appVersion: "2.2.0-beta.2", installedCasks: [])
        #expect(commands.first == "brew tap thaw-app/tap")
        #expect(commands.last == "brew install --cask thaw-app/tap/thaw@2-beta")
    }

    @Test("The prompt carries the commands for its snippet")
    func promptCarriesCommands() throws {
        let prompt = try #require(HomebrewTapNotice.prompt(appVersion: "2.2.0", installedCasks: ["thaw@beta"]))
        #expect(prompt.commands.first == "brew uninstall --cask thaw@beta")
        #expect(prompt.commands.last == "brew install --cask thaw-app/tap/thaw@2")
        #expect(!prompt.message.contains("brew tap"))
    }

    @MainActor
    @Test("The snippet is tall enough for every command line")
    func snippetFitsCommands() {
        let one = HomebrewTapNotice.snippetView(for: "brew tap thaw-app/tap")
        let four = HomebrewTapNotice.snippetView(for: Array(repeating: "brew tap thaw-app/tap", count: 4).joined(separator: "\n"))
        #expect(one.frame.width == 320)
        #expect(four.frame.height > one.frame.height * 2)
    }

    @Test("A Mac that already installs from the tap gets no notice")
    func tapInstallsSkipTheNotice() {
        #expect(HomebrewTapNotice.prompt(appVersion: "2.2.0", installedCasks: ["thaw@2"]) == nil)
        #expect(HomebrewTapNotice.prompt(appVersion: "2.2.0-beta.2", installedCasks: ["thaw", "thaw@2-beta"]) == nil)
    }

    @Test("Installed casks are read from the Caskroom folders")
    func installedCasksFromCaskroom() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("thaw@beta"), withIntermediateDirectories: true)

        let casks = HomebrewTapNotice.installedCasks(caskroomPaths: [root.path, "/nonexistent"])
        #expect(casks == ["thaw@beta"])
    }
}
