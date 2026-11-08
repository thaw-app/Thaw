//
//  DisplaySettingsManager+DisplayList.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 René Jiménez
//  Licensed under the GNU GPLv3

import Foundation

extension DisplaySettingsManager {
    /// Connected displays, then every saved one that isn't connected, each
    /// group alphabetical. A saved display without a remembered name is listed
    /// by its UUID, so its settings can still be reached or forgotten.
    var displays: [DisplayInfo] {
        let connected = connectedDisplays()
        let connectedIDs = Set(connected.map(\.id))
        let savedIDs = Set(knownDisplays.keys).union(configurations.keys).subtracting(connectedIDs)
        let disconnected = savedIDs.map { uuid in
            let known = knownDisplays[uuid]
            let name = known?.name.trimmingCharacters(in: .whitespaces) ?? ""
            return DisplayInfo(
                id: uuid,
                displayID: nil,
                name: name.isEmpty ? Self.unnamedDisplayName(uuid: uuid) : name,
                hasNotch: known?.hasNotch ?? false,
                isConnected: false
            )
        }
        return connected.sorted { $0.name < $1.name } + disconnected.sorted { $0.name < $1.name }
    }

    /// A label for a saved display whose name was never captured: the start of its UUID.
    static func unnamedDisplayName(uuid: String) -> String {
        String(localized: "Display \(String(uuid.prefix(8)))", comment: "A saved display with no known name; the placeholder is the start of its ID.")
    }

    /// Forgets a display that isn't connected: its settings and its remembered name.
    /// It comes back with the template's settings if it connects again.
    func forgetDisplay(uuid: String) {
        guard !connectedDisplays().contains(where: { $0.id == uuid }) else { return }
        var remainingConfigurations = configurations
        remainingConfigurations[uuid] = nil
        configurations = remainingConfigurations
        var remainingKnown = knownDisplays
        remainingKnown[uuid] = nil
        knownDisplays = remainingKnown
    }
}
