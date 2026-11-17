//
//  CaptureDiagnostics+Stored.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import ImageIO
import MenuBarModel
import os.lock
import UniformTypeIdentifiers

nonisolated extension CaptureDiagnostics {
    /// The file number each item's stored picture is saved under, so a new picture replaces the old one.
    private static let storedSlots = OSAllocatedUnfairLock(initialState: [String: Int]())

    /// How many items get a stored-picture file.
    private static let storedLimit = 96

    /// Saves the picture the cache keeps for an item, as stored-N.png: one file per item, replaced when the
    /// picture changes. The sampled crops are the first three attempts on an item, which for a hidden item
    /// are often blank ones from before it was shown, so they do not say what ended up in the Thaw Bar.
    static func recordStored(
        _ image: CGImage,
        item: MenuBarItem,
        isEnabled: Bool = DiagnosticLogger.shared.isEnabled,
        directory: URL = sampleDirectory
    ) {
        guard isEnabled, image.width <= 512, image.height <= 128 else { return }
        let key = "\(item.ownerPID):\(item.uniqueIdentifier)"
        let slot = storedSlots.withLock { slots -> Int? in
            if let slot = slots[key] { return slot }
            guard slots.count < storedLimit else { return nil }
            slots[key] = slots.count + 1
            return slots.count
        }
        guard let slot else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("stored-\(slot).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                return
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            NotificationCenter.default.post(name: didWriteSample, object: nil)
            DiagLog(category: "CaptureDiagnostics").info(
                "[CapturePixelTrace] stored item=\(item.uniqueIdentifier) owner=\(item.ownerPID) " +
                    "presence=\(String(describing: image.glyphPresenceOverNearUniformBackground())) raw=\(url.path)"
            )
        } catch {
            DiagLog(category: "CaptureDiagnostics").debug("[CapturePixelTrace] could not save stored picture: \(error)")
        }
    }
}
