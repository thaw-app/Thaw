//
//  LaunchAtLoginSetting.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import MenuBarModel
import Observation
import ServiceManagement

/// Keeps ServiceManagement's synchronous status query out of SwiftUI bindings.
@MainActor
@Observable
final class LaunchAtLoginSetting {
    private(set) var isEnabled = false
    private(set) var isLoaded = false
    private(set) var isUpdating = false

    @ObservationIgnored private var refreshGeneration = 0
    private let readStatus: @Sendable () async -> Bool
    private let writeStatus: @MainActor (Bool) -> Void

    private static nonisolated let diagLog = DiagLog(category: "LaunchAtLoginSetting")

    init(
        readStatus: @escaping @Sendable () async -> Bool = { await LaunchAtLoginSetting.readSystemStatus() },
        writeStatus: @escaping @MainActor (Bool) -> Void = { enabled in
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                LaunchAtLoginSetting.diagLog.error(
                    "Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                )
            }
        }
    ) {
        self.readStatus = readStatus
        self.writeStatus = writeStatus
    }

    func refresh() async {
        guard !isUpdating, !Task.isCancelled else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let enabled = await readStatus()
        guard !Task.isCancelled, generation == refreshGeneration else { return }
        isEnabled = enabled
        isLoaded = true
    }

    func setEnabled(_ enabled: Bool) async {
        guard isLoaded, !isUpdating, !Task.isCancelled else { return }
        refreshGeneration += 1
        isUpdating = true
        defer { isUpdating = false }
        writeStatus(enabled)
        // Registration can fail or require approval. Display the system's answer,
        // even if the user left the pane while this explicit change was pending.
        isEnabled = await readStatus()
    }

    @concurrent
    private static nonisolated func readSystemStatus() async -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
