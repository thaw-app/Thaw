//
//  SpaceIndicatorExtra.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// What Thaw sends the Space indicator. Must match SpaceIndicatorSnapshot in Thaw.
struct SpaceIndicatorSnapshot: Codable, Equatable {
    struct Space: Codable, Equatable {
        var label: String
        var isCurrent: Bool
    }

    struct Display: Codable, Equatable {
        var name: String
        var hasMenuBar: Bool
        var spaces: [Space]
    }

    var title: String
    var displays: [Display]
}

/// Must match Thaw's copy in SpaceIndicator.
enum SpaceIndicatorChannel {
    static func file(in folder: URL) -> URL {
        folder.appending(path: "space.json")
    }

    static func notification(parent: String) -> Notification.Name {
        Notification.Name("\(parent).extra.space.update")
    }

    /// Nil when Thaw hasn't written the file yet or it can't be read.
    static func read(from file: URL) -> SpaceIndicatorSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SpaceIndicatorSnapshot.self, from: data)
    }
}

/// The Space indicator's menu, as plain entries so it can be checked without AppKit.
enum SpaceIndicatorMenu {
    enum Entry: Equatable {
        case header(String)
        case space(String, isCurrent: Bool)
        case separator
        case missionControl
    }

    static func title(for snapshot: SpaceIndicatorSnapshot?) -> String {
        snapshot?.title ?? String(localized: "Space")
    }

    /// Display headings appear only with more than one display.
    static func entries(for snapshot: SpaceIndicatorSnapshot?) -> [Entry] {
        guard let snapshot else { return [.missionControl] }
        var entries: [Entry] = []
        for display in snapshot.displays {
            if snapshot.displays.count > 1 {
                entries.append(.header(display.hasMenuBar
                        ? String(localized: "\(display.name) (menu bar)", comment: "A display heading in the Space menu; this display has the menu bar.")
                        : display.name))
            }
            entries += display.spaces.map { .space($0.label, isCurrent: $0.isCurrent) }
        }
        return entries + [.separator, .missionControl]
    }
}

/// Draws the active Space's name and lists every Space in its menu. Thaw reads the Spaces and writes them to a file.
@MainActor
final class SpaceIndicatorExtra: NSObject {
    private weak var button: NSStatusBarButton?
    private let file: URL
    private var snapshot: SpaceIndicatorSnapshot?

    init(button: NSStatusBarButton, parentBundleIdentifier: String) {
        self.button = button
        file = SpaceIndicatorChannel.file(in: SlotStandInChannel.folder(parent: parentBundleIdentifier))
        super.init()
        button.imagePosition = .noImage
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(reload),
            name: SpaceIndicatorChannel.notification(parent: parentBundleIdentifier),
            object: nil
        )
        reload()
    }

    @objc private func reload() {
        snapshot = SpaceIndicatorChannel.read(from: file)
        let title = SpaceIndicatorMenu.title(for: snapshot)
        button?.title = title
        button?.toolTip = title
        button?.setAccessibilityValue(title)
    }

    func populate(_ menu: NSMenu) {
        menu.autoenablesItems = false
        for entry in SpaceIndicatorMenu.entries(for: snapshot) {
            switch entry {
            case let .header(title):
                menu.addItem(.sectionHeader(title: title))
            case let .space(label, isCurrent):
                let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                item.state = isCurrent ? .on : .off
                // macOS has no public way to switch Spaces, so the list reads as status, not buttons.
                item.isEnabled = false
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            case .missionControl:
                let item = NSMenuItem(title: String(localized: "Open Mission Control"), action: #selector(openMissionControl), keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
        }
    }

    @objc private func openMissionControl() {
        NSWorkspace.shared.openApplication(
            at: URL(filePath: "/System/Applications/Mission Control.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
