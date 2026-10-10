//
//  RecordingActivity.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - MicrophoneUser

/// One app macOS reports as running audio input right now.
///
/// Named, because the microphone is the half of this feature that can be:
/// CoreAudio's process object list carries a PID and a bundle identifier per
/// running input, so the app holding the microphone can be pointed at.
nonisolated struct MicrophoneUser: Equatable, Identifiable, Sendable {
    var id: pid_t {
        processIdentifier
    }

    let processIdentifier: pid_t
    let bundleIdentifier: String?

    /// The app's localized name, or a pid … stand-in for a process with no
    /// NSRunningApplication, a daemon, or one that exited between the list
    /// read and the lookup.
    let name: String
}

// MARK: - RecordingActivity

/// A single reading of what is listening or watching.
nonisolated struct RecordingActivity: Equatable, Sendable {
    /// Every process CoreAudio reports as running input, attributed.
    var microphoneUsers: [MicrophoneUser] = []

    /// Whether any camera reports itself as running.
    ///
    /// A bare Bool on purpose: no public API names the app holding a camera
    /// (see RecordingDeviceProbe), so this says only that one is on rather
    /// than guessing from whatever is frontmost.
    var isCameraInUse = false

    var isIdle: Bool {
        microphoneUsers.isEmpty && !isCameraInUse
    }
}

// MARK: - RecordingWatchAnnouncement

/// Something worth telling the user about, the moment it starts.
nonisolated enum RecordingWatchAnnouncement: Equatable, Sendable {
    /// A named app started running audio input.
    case microphoneOn(app: String)

    /// A camera started running. macOS names no owner, so neither does this.
    case cameraOn
}

// MARK: - RecordingWatchPolicy

/// Pure decision logic for what a change in RecordingActivity is worth
/// saying out loud, kept apart from the manager so the edge handling is
/// unit-testable without CoreAudio.
nonisolated enum RecordingWatchPolicy {
    /// The announcements owed for a move from old to new.
    ///
    /// Rising edges only. A device switching on is the event the user cannot
    /// afford to miss; switching off is covered by the standing readout in the
    /// control item menu, which does not interrupt.
    ///
    /// Microphone users are diffed by PID rather than by bundle identifier, so
    /// an app that stops and restarts input announces again, and two copies of
    /// the same app are two announcements.
    static func announcements(
        from old: RecordingActivity,
        to new: RecordingActivity
    ) -> [RecordingWatchAnnouncement] {
        let alreadyListening = Set(old.microphoneUsers.map(\.processIdentifier))

        var announcements = new.microphoneUsers
            .filter { !alreadyListening.contains($0.processIdentifier) }
            .map { RecordingWatchAnnouncement.microphoneOn(app: $0.name) }

        if new.isCameraInUse, !old.isCameraInUse {
            announcements.append(.cameraOn)
        }

        return announcements
    }
}
