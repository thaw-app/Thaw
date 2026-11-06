//
//  NotchClockWidget.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import SwiftUI
import ThawUI

/// Permission-free clock widget for checking descender behavior.
/// Refresh only while revealed; hidden descenders need no updates.
@MainActor
@Observable
final class NotchClockWidget: NotchWidget {
    let id = "clock"
    let refreshPolicy: NotchWidgetRefreshPolicy = .whileRevealed
    let bodySize = CGSize(width: 186, height: 62)

    private(set) var now = Date()

    /// Control Center hosts multiple modules, so the bundle ID alone cannot identify the clock.
    func matches(_ item: MenuBarItem) -> Bool {
        item.tag.namespace == .controlCenter
            && item.tag.title.localizedCaseInsensitiveContains("clock")
    }

    func isAvailable() -> Bool {
        true
    }

    var body: AnyView {
        AnyView(WidgetBody(widget: self))
    }

    /// A separate view tracks now so refreshes invalidate the displayed body.
    private struct WidgetBody: View {
        let widget: NotchClockWidget

        var body: some View {
            VStack(spacing: 1) {
                Text(widget.now.formatted(.dateTime.hour().minute().second()))
                    .font(.system(.title, weight: .light))
                    .monospacedDigit()
                Text(widget.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(ThawType.caption)
                    .foregroundStyle(ThawInk.supporting)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func refresh() {
        now = Date()
    }
}
