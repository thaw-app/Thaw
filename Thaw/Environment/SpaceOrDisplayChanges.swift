//
//  SpaceOrDisplayChanges.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import Combine

extension DisplayEnvironment {
    /// Sends at each active-Space change and at each send of display, for panels
    /// that drop or re-place themselves on either.
    static func spaceOrDisplayChanges(
        merging display: some Publisher<Void, Never>,
        center: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) -> AnyPublisher<Void, Never> {
        center.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .map { _ in () }
            .merge(with: display)
            .eraseToAnyPublisher()
    }
}
