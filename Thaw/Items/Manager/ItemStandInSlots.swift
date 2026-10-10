//
//  ItemStandInSlots.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import MenuBarModel

/// One of the fixed stand-in bundles for third-party items macOS won't draw.
///
/// macOS 27 hides and orders items per bundle, and a bundle identifier cannot
/// be made up at runtime without breaking the signature, so a fixed set of
/// slot bundles ships inside the app. Must match ExtraRole and
/// SlotStandInChannel in ThawExtraHelper.
nonisolated struct ItemStandInSlot: Hashable, Comparable {
    static let all = (1 ... 6).map(ItemStandInSlot.init(number:))

    let number: Int

    var bundleIdentifier: String {
        "\(ThawMenuBarIdentity.bundleIdentifier).extra.slot\(number)"
    }

    var autosaveName: String {
        "Thaw.Extra.Slot\(number)"
    }

    /// The persistent identifier the stand-in's item gets in the layout.
    var itemIdentifier: String {
        MenuBarItemTag.canonicalPersistentIdentifier("\(bundleIdentifier):\(autosaveName)")
    }

    var bundleURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Library/Extras/Thaw Stand-In \(number).app")
    }

    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: ThawMenuBarIdentity.bundleIdentifier).appending(path: "StandIns")
    }

    var updateNotification: Notification.Name {
        Notification.Name("\(ThawMenuBarIdentity.bundleIdentifier).extra.slot\(number).update")
    }

    static var clickNotification: Notification.Name {
        Notification.Name("\(ThawMenuBarIdentity.bundleIdentifier).extra.slot.clicked")
    }

    static func < (lhs: ItemStandInSlot, rhs: ItemStandInSlot) -> Bool {
        lhs.number < rhs.number
    }

    /// The slot a bundle identifier belongs to, if it is one.
    init?(bundleIdentifier: String) {
        let prefix = "\(ThawMenuBarIdentity.bundleIdentifier).extra.slot"
        guard bundleIdentifier.hasPrefix(prefix), let number = Int(bundleIdentifier.dropFirst(prefix.count)),
              (1 ... 6).contains(number)
        else { return nil }
        self.number = number
    }

    /// The slot a menu bar item belongs to, if it is a stand-in.
    init?(tag: MenuBarItemTag) {
        guard case let .string(bundleIdentifier) = tag.namespace else { return nil }
        self.init(bundleIdentifier: bundleIdentifier)
    }

    /// The name of the item a stand-in draws, for MenuBarItem.displayName.
    static func label(for tag: MenuBarItemTag) -> String? {
        guard let slot = ItemStandInSlot(tag: tag) else { return nil }
        let labels = UserDefaults.standard.dictionary(forKey: ItemStandInSlots.labelsKey) as? [String: String]
        return labels?[slot.bundleIdentifier]
    }

    private init(number: Int) {
        self.number = number
    }
}

/// Puts Thaw Bar Only items the user asked for back in the menu bar, each as
/// its own stand-in bundle that hides and moves like any app's item.
///
/// A slot is held for its item until the item leaves Thaw Bar Only or the user
/// turns it off, so the stand-in keeps its place across launches. The helper
/// runs only while the real item is live, since both its icon and its click
/// come from the real item.
///
/// A slot's place in the bar and its custom name belong to the slot, not the
/// item. An item that comes back gets its old slot where it can, a new item
/// gets the slot left unused longest, and a slot handed to a different item
/// starts over at the left end of Visible without the old item's name.
@MainActor
final class ItemStandInSlots {
    private static let assignmentsKey = "MenuBarItemManager.itemStandInSlots"
    /// Slot bundle identifier to the real item's name, readable off the main
    /// actor for MenuBarItem.displayName.
    static nonisolated let labelsKey = "MenuBarItemManager.itemStandInLabels"

    private let log = DiagLog(category: "ItemStandInSlots")
    private weak var appState: AppState?

    /// Slot number to the canonical identifier of the item it stands in for.
    private var assignments: [Int: String]
    /// What each running helper was last given, so an unchanged icon is not
    /// rewritten on every item-cache change.
    private var published: [Int: Data] = [:]
    /// Slot number to the last item it stood in for, kept after release.
    private var lastOccupants: [Int: String]
    /// Released slots, longest unused first.
    private var releaseOrder: [Int]
    /// Slots handed to a different item, still to be moved to Visible's left end.
    private var pendingReseats: Set<Int>
    private var reseating: Set<Int> = []
    private var clickObserver: NSObjectProtocol?

    init() {
        assignments = Self.loadSlotMap(forKey: Self.assignmentsKey)
        lastOccupants = Self.loadSlotMap(forKey: "\(Self.assignmentsKey).last")
        releaseOrder = UserDefaults.standard.array(forKey: "\(Self.assignmentsKey).released") as? [Int] ?? []
        pendingReseats = Set(UserDefaults.standard.array(forKey: "\(Self.assignmentsKey).reseat") as? [Int] ?? [])
    }

    private static func loadSlotMap(forKey key: String) -> [Int: String] {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        clickObserver = DistributedNotificationCenter.default().addObserver(
            forName: ItemStandInSlot.clickNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let slot = notification.userInfo?["slot"] as? Int
            let isRightClick = notification.userInfo?["right"] as? Bool ?? false
            MainActor.assumeIsolated {
                guard let slot else { return }
                self?.standInClicked(slot: slot, isRightClick: isRightClick)
            }
        }
    }

    /// The slot standing in for identifier, if any.
    func slot(for identifier: String) -> ItemStandInSlot? {
        assignments.first { $0.value == identifier }.flatMap { entry in
            ItemStandInSlot.all.first { $0.number == entry.key }
        }
    }

    /// Brings the running stand-ins in line with wanted: the canonical
    /// identifiers the user wants in the menu bar, with their live items.
    func reconcile(wanted: Set<String>, liveItems: [String: MenuBarItem]) {
        guard let appState else { return }

        for (number, identifier) in assignments where !wanted.contains(identifier) {
            release(number)
        }
        for identifier in wanted.sorted() where slot(for: identifier) == nil {
            guard let free = freeSlot(for: identifier) else {
                log.warning("No free stand-in slot for \(identifier); all \(ItemStandInSlot.all.count) are in use")
                continue
            }
            assign(free, to: identifier)
        }
        persistAssignments()

        for slot in ItemStandInSlot.all {
            guard let identifier = assignments[slot.number] else { continue }
            guard let item = liveItems[identifier] else {
                // The real item is gone, so nothing could be clicked; the slot
                // stays held and the helper returns with the item.
                stop(slot)
                continue
            }
            publish(item, to: slot, appState: appState)
            launchIfNeeded(slot)
            reseatIfNeeded(slot, appState: appState)
        }
    }

    /// The item's own last slot, else a slot never used, else the one
    /// released longest ago.
    private func freeSlot(for identifier: String) -> Int? {
        let free = ItemStandInSlot.all.map(\.number).filter { assignments[$0] == nil }
        return free.first { lastOccupants[$0] == identifier }
            ?? free.first { lastOccupants[$0] == nil }
            ?? releaseOrder.first { free.contains($0) }
            ?? free.first
    }

    private func assign(_ number: Int, to identifier: String) {
        if let previous = lastOccupants[number], previous != identifier {
            forgetCustomName(ofSlot: number)
            pendingReseats.insert(number)
        }
        assignments[number] = identifier
        lastOccupants[number] = identifier
        releaseOrder.removeAll { $0 == number }
        log.info("Assigned stand-in slot \(number) to \(identifier)")
    }

    /// Moves a slot that changed items to the left end of Visible, once its
    /// helper's item is on the bar.
    private func reseatIfNeeded(_ slot: ItemStandInSlot, appState: AppState) {
        guard pendingReseats.contains(slot.number), !reseating.contains(slot.number) else { return }
        let visible = appState.itemManager.managedItems(for: .visible).sorted { $0.bounds.minX < $1.bounds.minX }
        guard let standIn = visible.first(where: { $0.tag.namespace == .string(slot.bundleIdentifier) }),
              let leftmost = visible.first
        else { return }
        guard leftmost != standIn else {
            pendingReseats.remove(slot.number)
            persistAssignments()
            return
        }
        reseating.insert(slot.number)
        // One attempt: a declined write would otherwise repeat on every cache
        // change, and the slot is still in Visible either way.
        pendingReseats.remove(slot.number)
        persistAssignments()
        Task { [weak self, log] in
            defer { self?.reseating.remove(slot.number) }
            do {
                let moved = try await appState.itemManager.move(
                    item: standIn,
                    to: .leftOfItem(leftmost),
                    allowSyntheticDrag: false
                )
                if moved {
                    log.info("Moved stand-in slot \(slot.number) to the left end of Visible for its new item")
                } else {
                    log.warning("Stand-in slot \(slot.number) kept its old place; the move was declined")
                }
            } catch {
                log.warning("Could not move stand-in slot \(slot.number): \(error)")
            }
        }
    }

    /// The name the user gave the stand-in belongs to the item it stood in for.
    private func forgetCustomName(ofSlot number: Int) {
        guard let slot = ItemStandInSlot.all.first(where: { $0.number == number }) else { return }
        var names = Defaults.dictionary(forKey: .menuBarItemCustomNames) as? [String: String] ?? [:]
        let stale = names.keys.filter { $0.hasPrefix("\(slot.bundleIdentifier):") }
        guard !stale.isEmpty else { return }
        stale.forEach { names[$0] = nil }
        Defaults.set(names, forKey: .menuBarItemCustomNames)
    }

    /// Keeps slots with their items when the items come back under a new
    /// identifier. See MenuBarItemManager.followRenamedThawBarOnlyItems().
    func follow(_ renames: [(from: String, to: String)]) {
        for rename in renames {
            for (number, identifier) in assignments where identifier == rename.from {
                assignments[number] = rename.to
            }
            for (number, identifier) in lastOccupants where identifier == rename.from {
                lastOccupants[number] = rename.to
            }
        }
        persistAssignments()
    }

    private func release(_ number: Int) {
        assignments[number] = nil
        releaseOrder.removeAll { $0 == number }
        releaseOrder.append(number)
        if let slot = ItemStandInSlot.all.first(where: { $0.number == number }) {
            stop(slot)
            setLabel(nil, for: slot)
            UserDefaults.standard.removeObject(forKey: "\(Self.assignmentsKey).placed.\(number)")
        }
        log.info("Released stand-in slot \(number)")
    }

    private func persistAssignments() {
        func stored(_ map: [Int: String]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        }
        UserDefaults.standard.set(stored(assignments), forKey: Self.assignmentsKey)
        UserDefaults.standard.set(stored(lastOccupants), forKey: "\(Self.assignmentsKey).last")
        UserDefaults.standard.set(releaseOrder, forKey: "\(Self.assignmentsKey).released")
        UserDefaults.standard.set(pendingReseats.sorted(), forKey: "\(Self.assignmentsKey).reseat")
    }

    private func setLabel(_ label: String?, for slot: ItemStandInSlot) {
        var labels = UserDefaults.standard.dictionary(forKey: Self.labelsKey) as? [String: String] ?? [:]
        labels[slot.bundleIdentifier] = label
        UserDefaults.standard.set(labels, forKey: Self.labelsKey)
    }

    /// Writes the item's icon and name where the helper reads them, and tells
    /// the helper when they changed.
    private func publish(_ item: MenuBarItem, to slot: ItemStandInSlot, appState: AppState) {
        guard let image = OverflowFallbackIcon.preferredImage(for: item, appState: appState),
              let png = Self.pngData(for: image)
        else { return }
        let label = item.displayName
        var fingerprint = png
        fingerprint.append(Data(label.utf8))
        fingerprint.append(image.isTemplate ? 1 : 0)
        guard published[slot.number] != fingerprint else { return }

        let folder = ItemStandInSlot.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appending(path: "slot\(slot.number).png"), options: .atomic)
            try Data(label.utf8).write(to: folder.appending(path: "slot\(slot.number).txt"), options: .atomic)
            let templateMarker = folder.appending(path: "slot\(slot.number).template")
            if image.isTemplate {
                try Data().write(to: templateMarker)
            } else {
                try? FileManager.default.removeItem(at: templateMarker)
            }
        } catch {
            log.error("Could not write stand-in slot \(slot.number): \(error)")
            return
        }
        published[slot.number] = fingerprint
        setLabel(label, for: slot)
        DistributedNotificationCenter.default().postNotificationName(
            slot.updateNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func launchIfNeeded(_ slot: ItemStandInSlot) {
        guard let appState,
              NSRunningApplication.runningApplications(withBundleIdentifier: slot.bundleIdentifier).isEmpty,
              FileManager.default.fileExists(atPath: slot.bundleURL.path)
        else { return }
        // Known and in Visible before its item first appears, so it is neither
        // filed as a new arrival nor born into a concealed section.
        if appState.itemManager.knownItemIdentifiers.insert(slot.itemIdentifier).inserted {
            appState.itemManager.persistKnownItemIdentifiers()
        }
        if appState.menuBarManager.sectionController.authoredSection(for: slot.itemIdentifier) != .visible,
           !UserDefaults.standard.bool(forKey: "\(Self.assignmentsKey).placed.\(slot.number)")
        {
            appState.menuBarManager.assignSection(.visible, identifier: slot.itemIdentifier)
            UserDefaults.standard.set(true, forKey: "\(Self.assignmentsKey).placed.\(slot.number)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.arguments = ["--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        Task { [log] in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: slot.bundleURL, configuration: configuration)
                log.info("Launched stand-in slot \(slot.number)")
            } catch {
                log.error("Could not launch stand-in slot \(slot.number): \(error)")
            }
        }
    }

    private func stop(_ slot: ItemStandInSlot) {
        published[slot.number] = nil
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: slot.bundleIdentifier) {
            app.terminate()
        }
    }

    private func standInClicked(slot number: Int, isRightClick: Bool) {
        guard let appState, let identifier = assignments[number],
              let item = appState.itemManager.thawBarOnlyItems.first(where: {
                  MenuBarItemTag.canonicalPersistentIdentifier($0.uniqueIdentifier) == identifier
              })
        else { return }
        let slot = ItemStandInSlot.all.first { $0.number == number }
        let standIn = slot.flatMap { slot in
            appState.itemManager.itemCache.managedItems.first { $0.tag.namespace == .string(slot.bundleIdentifier) }
        }
        let displayID = standIn.flatMap { standIn in
            NSScreen.screens.first { $0.frame.contains(standIn.bounds.origin) }?.displayID
        }
            ?? NSScreen.screenWithActiveMenuBar?.displayID
            ?? CGMainDisplayID()
        log.info("Stand-in slot \(number) clicked for \(item.logString)")
        Task {
            await appState.itemManager.clickConcealedItem(item: item, with: isRightClick ? .right : .left, on: displayID)
        }
    }

    /// PNG at menu bar height and 2x, so an app icon is not handed over at
    /// 1024 pt and a small asset stays sharp.
    private static func pngData(for image: NSImage) -> Data? {
        guard image.size.height > 0 else { return nil }
        let height: CGFloat = min(image.size.height, 18)
        let size = NSSize(width: image.size.width * height / image.size.height, height: height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * 2).rounded(.up)),
            pixelsHigh: Int((size.height * 2).rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
