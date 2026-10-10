//
//  RecordingWatchPolicyTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Testing
@testable import Thaw

/// RecordingWatchPolicy is the whole of what the watcher decides, the
/// rest is CoreAudio reads and a capsule, so the edge handling is pinned
/// here rather than left to a live microphone.
@Suite("Recording watch policy")
struct RecordingWatchPolicyTests {
    private func user(_ pid: pid_t, _ name: String) -> MicrophoneUser {
        MicrophoneUser(processIdentifier: pid, bundleIdentifier: "com.example.\(name)", name: name)
    }

    // MARK: - Rising edges

    @Test("An app taking the microphone is announced by name")
    func microphoneRiseAnnouncesTheApp() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(),
            to: RecordingActivity(microphoneUsers: [user(42, "Droppy")])
        )

        #expect(announcements == [.microphoneOn(app: "Droppy")])
    }

    @Test("A camera turning on is announced without an owner")
    func cameraRiseAnnouncesPresenceOnly() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(),
            to: RecordingActivity(isCameraInUse: true)
        )

        #expect(announcements == [.cameraOn])
    }

    @Test("Both devices starting at once announce both")
    func bothDevicesRise() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(),
            to: RecordingActivity(microphoneUsers: [user(42, "Zoom")], isCameraInUse: true)
        )

        #expect(announcements == [.microphoneOn(app: "Zoom"), .cameraOn])
    }

    // MARK: - Steady state

    @Test("A device that was already on announces nothing")
    func steadyStateIsSilent() {
        let live = RecordingActivity(microphoneUsers: [user(42, "Zoom")], isCameraInUse: true)

        #expect(RecordingWatchPolicy.announcements(from: live, to: live).isEmpty)
    }

    @Test("Nothing happening announces nothing")
    func idleIsSilent() {
        #expect(
            RecordingWatchPolicy.announcements(
                from: RecordingActivity(),
                to: RecordingActivity()
            ).isEmpty
        )
    }

    // MARK: - Falling edges

    @Test("Releasing the microphone is not announced")
    func microphoneFallIsSilent() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(microphoneUsers: [user(42, "Zoom")]),
            to: RecordingActivity()
        )

        #expect(announcements.isEmpty)
    }

    @Test("A camera switching off is not announced")
    func cameraFallIsSilent() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(isCameraInUse: true),
            to: RecordingActivity()
        )

        #expect(announcements.isEmpty)
    }

    // MARK: - Multiple listeners

    @Test("A second app joining announces only the newcomer")
    func onlyTheNewListenerIsAnnounced() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(microphoneUsers: [user(42, "Zoom")]),
            to: RecordingActivity(microphoneUsers: [user(42, "Zoom"), user(77, "Droppy")])
        )

        #expect(announcements == [.microphoneOn(app: "Droppy")])
    }

    @Test("One of two apps dropping out leaves the other silent")
    func partialFallIsSilent() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(microphoneUsers: [user(42, "Zoom"), user(77, "Droppy")]),
            to: RecordingActivity(microphoneUsers: [user(42, "Zoom")])
        )

        #expect(announcements.isEmpty)
    }

    /// Two copies of one app are two announcements, and a relaunch is a fresh
    /// one, which is why the diff is keyed on PID and not on the name or the
    /// bundle identifier.
    @Test("A relaunched app under a new PID announces again")
    func relaunchUnderANewPIDAnnouncesAgain() {
        let announcements = RecordingWatchPolicy.announcements(
            from: RecordingActivity(microphoneUsers: [user(42, "Zoom")]),
            to: RecordingActivity(microphoneUsers: [user(99, "Zoom")])
        )

        #expect(announcements == [.microphoneOn(app: "Zoom")])
    }

    // MARK: - Idle

    @Test("Activity is idle only when neither device is in use")
    func idlenessCoversBothDevices() {
        #expect(RecordingActivity().isIdle)
        #expect(!RecordingActivity(isCameraInUse: true).isIdle)
        #expect(!RecordingActivity(microphoneUsers: [user(42, "Zoom")]).isIdle)
    }
}
