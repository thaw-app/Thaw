//
//  MenuBarPointerAXCache.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreGraphics
import Foundation
import MenuBarModel

/// Accessibility answers the input taps read without waiting for them.
///
/// The taps run on the main run loop and every event in the system queues
/// behind them, so they cannot make an AX round trip. They read the last
/// answer here instead. A miss starts a refresh through MenuBarAXQueries
/// and reports "unknown", which callers read the way they read a failed AX
/// read. Paths that can afford to wait await a fresh answer.
@MainActor
final class MenuBarPointerAXCache {
    private struct ForeignWidgetAnswer {
        let location: CGPoint
        let isForeign: Bool
        let answeredAt: ContinuousClock.Instant
    }

    private struct ApplicationMenuAnswer {
        let pid: pid_t
        let frames: [CGRect]?
        let answeredAt: ContinuousClock.Instant
    }

    /// How far the pointer may drift from where a hit-test was answered and
    /// still reuse it. A click lands where the pointer already rested.
    private static let locationTolerance: CGFloat = 3

    /// How long a hit-test answer stays good: long enough to span the moves
    /// before a click, short enough that a widget appearing is noticed.
    private static let foreignWidgetLifetime: Duration = .milliseconds(750)

    /// Menu titles rarely change without the app changing, but they do (a
    /// document switch, a mode change), so an old answer is refreshed in the
    /// background while it is still being served.
    private static let applicationMenuRefreshAge: Duration = .seconds(2)

    private var foreignWidget: ForeignWidgetAnswer?
    private var foreignWidgetTask: Task<Void, Never>?
    private var queuedForeignWidgetLocation: CGPoint?

    private var applicationMenu: ApplicationMenuAnswer?
    private var applicationMenuTask: Task<Void, Never>?
    private var applicationMenuTaskPID: pid_t?

    // MARK: Foreign widget

    /// The cached answer for location, or nil when there is none yet, in
    /// which case a refresh is started for it.
    func foreignWidget(at location: CGPoint) -> Bool? {
        if let answer = foreignWidget,
           answer.location.distance(to: location) <= Self.locationTolerance,
           answer.answeredAt.duration(to: .now) < Self.foreignWidgetLifetime
        {
            return answer.isForeign
        }
        refreshForeignWidget(at: location)
        return nil
    }

    /// Starts a hit-test for location. One runs at a time; a request made
    /// meanwhile replaces any other waiting one, so a moving pointer is
    /// answered for where it ended up, not for every point it crossed.
    func refreshForeignWidget(at location: CGPoint) {
        guard foreignWidgetTask == nil else {
            queuedForeignWidgetLocation = location
            return
        }
        foreignWidgetTask = Task { [weak self] in
            let isForeign = await MenuBarAXQueries.isForeignWidget(at: location)
            guard let self else { return }
            foreignWidget = ForeignWidgetAnswer(location: location, isForeign: isForeign, answeredAt: .now)
            foreignWidgetTask = nil
            if let next = queuedForeignWidgetLocation {
                queuedForeignWidgetLocation = nil
                refreshForeignWidget(at: next)
            }
        }
    }

    /// A fresh answer for location, for callers that can wait for it.
    func isForeignWidget(at location: CGPoint) async -> Bool {
        let isForeign = await MenuBarAXQueries.isForeignWidget(at: location)
        foreignWidget = ForeignWidgetAnswer(location: location, isForeign: isForeign, answeredAt: .now)
        return isForeign
    }

    // MARK: Application menu

    /// The cached title frames of pid's menu bar, or nil when they are not
    /// known yet or could not be read. A miss or an old answer starts a refresh.
    func applicationMenuFrames(for pid: pid_t) -> [CGRect]? {
        guard let answer = applicationMenu, answer.pid == pid else {
            refreshApplicationMenu(for: pid)
            return nil
        }
        if answer.answeredAt.duration(to: .now) >= Self.applicationMenuRefreshAge {
            refreshApplicationMenu(for: pid)
        }
        return answer.frames
    }

    /// Starts reading pid's menu bar unless that read is already running.
    /// A read for another app is superseded: only the menu bar owner matters.
    func refreshApplicationMenu(for pid: pid_t) {
        guard applicationMenuTask == nil || applicationMenuTaskPID != pid else {
            return
        }
        applicationMenuTask?.cancel()
        applicationMenuTaskPID = pid
        applicationMenuTask = Task { [weak self] in
            let frames = await MenuBarAXQueries.applicationMenuFrames(pid: pid)
            guard let self, !Task.isCancelled else { return }
            applicationMenu = ApplicationMenuAnswer(pid: pid, frames: frames, answeredAt: .now)
            applicationMenuTask = nil
            applicationMenuTaskPID = nil
        }
    }
}
