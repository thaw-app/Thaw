//
//  HomebrewTapNotice.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// A one-time alert that Thaw 2 installs from the thaw-app/tap Homebrew tap, since
/// Homebrew's thaw cask moves to Thaw 3 and its macOS 27 requirement.
enum HomebrewTapNotice {
    static nonisolated let caskroomPaths = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
    static nonisolated let mainRepositoryCasks = ["thaw", "thaw@beta"]
    static nonisolated let tapCasks = ["thaw@2", "thaw@2-beta"]

    nonisolated struct Prompt: Equatable {
        let title: String
        let message: String
        let commands: [String]
    }

    /// The tap cask matching the running build: betas and release candidates follow thaw@2-beta.
    static nonisolated func tapCask(forAppVersion version: String) -> String {
        version.contains("-beta") || version.contains("-rc") ? "thaw@2-beta" : "thaw@2"
    }

    /// The commands that move this Mac to the tap, uninstalling any main-repository cask first.
    static nonisolated func commands(appVersion: String, installedCasks: Set<String>) -> [String] {
        let cask = "thaw-app/tap/" + tapCask(forAppVersion: appVersion)
        let uninstalls = mainRepositoryCasks.filter(installedCasks.contains).map { "brew uninstall --cask \($0)" }
        return uninstalls + ["brew tap thaw-app/tap", "brew trust --cask \(cask)", "brew install --cask \(cask)"]
    }

    /// The prompt, or nil when the app already came from the tap.
    static nonisolated func prompt(appVersion: String, installedCasks: Set<String>) -> Prompt? {
        guard installedCasks.isDisjoint(with: tapCasks) else {
            return nil
        }
        return Prompt(
            title: String(localized: "Thaw 2 Has Its Own Homebrew Tap"),
            message: String(
                localized: """
                Homebrew's thaw cask moves to Thaw 3 when 3.0.0 is released, and Thaw 3 needs macOS 27. If you installed Thaw with Homebrew, run these commands in Terminal to stay on Thaw 2. Your settings stay. Without Homebrew there's nothing to do.
                """
            ),
            commands: commands(appVersion: appVersion, installedCasks: installedCasks)
        )
    }

    /// The Thaw casks present in Homebrew's Caskroom folders.
    static nonisolated func installedCasks(caskroomPaths: [String] = caskroomPaths) -> Set<String> {
        Set((mainRepositoryCasks + tapCasks).filter { cask in
            caskroomPaths.contains { FileManager.default.fileExists(atPath: "\($0)/\(cask)") }
        })
    }

    @MainActor
    static func showIfNeeded() {
        guard !Defaults.bool(forKey: .hasSeenHomebrewTapNotice) else {
            return
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard let prompt = prompt(appVersion: version, installedCasks: installedCasks()) else {
            Defaults.set(true, forKey: .hasSeenHomebrewTapNotice)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.accessoryView = snippetView(for: prompt.commands.joined(separator: "\n"))
        alert.addButton(withTitle: String(localized: "Copy Commands"))
        alert.addButton(withTitle: String(localized: "Continue"))

        let response = alert.runModal()
        // Marked seen only once answered, so quitting during the alert shows it again next launch.
        Defaults.set(true, forKey: .hasSeenHomebrewTapNotice)
        guard response == .alertFirstButtonReturn else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt.commands.joined(separator: "\n"), forType: .string)
    }

    /// The commands in a monospaced, selectable box, like a code block.
    @MainActor
    static func snippetView(for text: String) -> NSView {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.isSelectable = true
        label.lineBreakMode = .byCharWrapping
        label.translatesAutoresizingMaskIntoConstraints = false

        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 6
        box.borderColor = .separatorColor
        box.fillColor = .textBackgroundColor
        box.contentViewMargins = NSSize(width: 8, height: 6)
        box.contentView?.addSubview(label)
        if let content = box.contentView {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                label.topAnchor.constraint(equalTo: content.topAnchor),
                label.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        let width: CGFloat = 320
        label.preferredMaxLayoutWidth = width - 16
        let height = label.intrinsicContentSize.height + 12
        box.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return box
    }
}
