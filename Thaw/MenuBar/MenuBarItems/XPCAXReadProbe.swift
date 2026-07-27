//
//  XPCAXReadProbe.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Cocoa
import Combine
import MenuBarModel

/// Verification probe for out-of-process Accessibility reads on macOS 27.
///
/// Before the real reads are migrated off the main actor and behind the XPC
/// service, this proves the path actually works end to end: that the service
/// connects, holds Accessibility permission, and returns snapshots that match
/// what Thaw enumerates in process. It only *reads* and *logs* — it never feeds
/// the result into item management, so it cannot break enumeration while the
/// service's 27 behavior is still unconfirmed.
///
/// Enable with:
///
///     defaults write com.stonerl.Thaw.debug Thaw.debugXPCAXReads -bool true
@MainActor
final class XPCAXReadProbe {
    static let shared = XPCAXReadProbe()

    private weak var appState: AppState?
    private var cancellable: AnyCancellable?
    private var inFlight = false

    private let diagLog = DiagLog(category: "XPCAXReadProbe")

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Defaults.Key.debugXPCAXReads.rawValue)
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        cancellable = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard isEnabled, !inFlight, let appState else { return }
        let items = appState.itemManager.itemCache.managedItems
        let pids = Set(items.map(\.ownerPID))
        guard !pids.isEmpty else { return }

        inFlight = true
        let inProcessCount = items.count
        Task { [weak self] in
            let snapshots = await MenuBarItemService.Connection.shared.menuBarItemSnapshots(for: Array(pids))
            await MainActor.run {
                guard let self else { return }
                self.diagLog.notice(
                    "XPC AX read: \(pids.count) pid(s) → \(snapshots.count) snapshot(s) (in-process items: \(inProcessCount))"
                )
                if let sample = snapshots.first {
                    let frame = sample.frame.map { NSStringFromRect($0) } ?? "nil"
                    self.diagLog.notice(
                        "XPC AX read sample: id=\(sample.identifier ?? "nil") role=\(sample.role ?? "nil") "
                            + "desc=\(sample.axDescription ?? "nil") frame=\(frame)"
                    )
                } else if !pids.isEmpty {
                    self.diagLog.notice(
                        "XPC AX read returned nothing — service not connected, no AX permission, or empty extras bar"
                    )
                }
                self.inFlight = false
            }
        }
    }
}
