//
//  ImageRecaptureTriggers.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

/// The changes the image cache answers with a debounced recapture of its own.
///
/// A display change is not one of them: the display-change coordinator recaptures once per settled change.
enum ImageRecaptureTriggers {
    /// Sends at each active-Space change and at each send of itemCacheChanges.
    static func changes(
        itemCacheChanges: some Publisher<Void, Never>,
        center: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) -> AnyPublisher<Void, Never> {
        center.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .map { _ in () }
            .merge(with: itemCacheChanges)
            .eraseToAnyPublisher()
    }
}
