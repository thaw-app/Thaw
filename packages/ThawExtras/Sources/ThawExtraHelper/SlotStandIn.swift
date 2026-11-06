//
//  SlotStandIn.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Thaw shares icon/name files and update notifications; clicks return to Thaw to open the real item.
/// Each slot has its own bundle so it hides and moves like an app item.
@MainActor
final class SlotStandIn: NSObject {
    private let slot: Int
    private let parentBundleIdentifier: String
    private weak var button: NSStatusBarButton?

    init(slot: Int, parentBundleIdentifier: String, button: NSStatusBarButton) {
        self.slot = slot
        self.parentBundleIdentifier = parentBundleIdentifier
        self.button = button
        super.init()
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(reload),
            name: SlotStandInChannel.updateName(parent: parentBundleIdentifier, slot: slot),
            object: nil
        )
        reload()
    }

    @objc private func reload() {
        let folder = SlotStandInChannel.folder(parent: parentBundleIdentifier)
        let label = (try? String(contentsOf: folder.appending(path: "slot\(slot).txt"), encoding: .utf8)) ?? ""
        let image = NSImage(contentsOf: folder.appending(path: "slot\(slot).png"))
            ?? NSImage(systemSymbolName: "square.dashed", accessibilityDescription: label)
        if FileManager.default.fileExists(atPath: folder.appending(path: "slot\(slot).template").path) {
            image?.isTemplate = true
        }
        if let image, image.size.height > 18 {
            image.size = NSSize(width: image.size.width * 18 / image.size.height, height: 18)
        }
        button?.image = image
        button?.toolTip = label
        button?.setAccessibilityLabel(label)
    }

    @objc private func clicked(_: NSStatusBarButton) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        DistributedNotificationCenter.default().postNotificationName(
            SlotStandInChannel.clickName(parent: parentBundleIdentifier),
            object: nil,
            userInfo: ["slot": slot, "right": isRightClick],
            deliverImmediately: true
        )
    }
}

/// Channel names must match Thaw's copy in ItemStandInSlot.
enum SlotStandInChannel {
    static func folder(parent: String) -> URL {
        URL.applicationSupportDirectory.appending(path: parent).appending(path: "StandIns")
    }

    static func updateName(parent: String, slot: Int) -> Notification.Name {
        Notification.Name("\(parent).extra.slot\(slot).update")
    }

    static func clickName(parent: String) -> Notification.Name {
        Notification.Name("\(parent).extra.slot.clicked")
    }
}

/// Which of Thaw's extra bundles it wants hidden. Must match Thaw's copy in
/// SystemExtraStandIns.
enum ExtraVisibilityChannel {
    static func hiddenBundles(parent: String) -> Set<String> {
        let file = SlotStandInChannel.folder(parent: parent).appending(path: "hidden-extras.txt")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }

    static func notification(parent: String) -> Notification.Name {
        Notification.Name("\(parent).extra.visibility")
    }
}
