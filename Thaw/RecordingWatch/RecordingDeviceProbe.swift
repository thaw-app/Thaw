//
//  RecordingDeviceProbe.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreAudio
import CoreMediaIO
import Foundation

// MARK: - RecordingDeviceProbe

/// Reads who is using the microphone and whether a camera is running, using
/// public API only.
///
/// The microphone is attributed per process via
/// kAudioHardwarePropertyProcessObjectList (macOS 14.4+), with no entitlement
/// or TCC prompt. The camera is presence only: the CMIO running flag has no
/// owner, and on macOS 27 the privacy indicator exposes no AX element either.
///
/// Both reads are synchronous IPC, so callers run them off the main actor.
nonisolated enum RecordingDeviceProbe {
    /// No display name: resolving one needs NSRunningApplication on the main
    /// actor. MicrophoneUser is the named form.
    struct Input: Equatable, Sendable {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
    }

    // MARK: Microphone

    /// Every process currently running audio input. Returns empty rather than
    /// throwing when unreadable, since an error capsule would be unactionable.
    static func microphoneInputs() -> [Input] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = audioAddress(kAudioHardwarePropertyProcessObjectList)

        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
            size > 0
        else {
            return []
        }

        var objects = [AudioObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }

        return objects.compactMap { object in
            // Running-input first, so only the few that answer true cost more reads.
            guard
                audioValue(object, kAudioProcessPropertyIsRunningInput, initial: UInt32(0)) == 1,
                let pid = audioValue(object, kAudioProcessPropertyPID, initial: pid_t(0))
            else {
                return nil
            }
            return Input(
                processIdentifier: pid,
                bundleIdentifier: audioString(object, kAudioProcessPropertyBundleID)
            )
        }
    }

    // MARK: Camera

    /// Whether any video device reports itself as running.
    ///
    /// Enumerating devices and reading their state is not capture, so this
    /// neither requires camera access nor prompts for it.
    static func isCameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = cmioAddress(UInt32(kCMIOHardwarePropertyDevices))

        var size: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
            size > 0
        else {
            return false
        }

        var devices = [CMIOObjectID](
            repeating: 0,
            count: Int(size) / MemoryLayout<CMIOObjectID>.size
        )
        var used: UInt32 = 0
        guard
            CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr
        else {
            return false
        }

        return devices.contains { isRunning($0) }
    }

    private static func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = cmioAddress(UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var running: UInt32 = 0
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &running) { pointer in
            CMIOObjectGetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &used,
                pointer
            )
        }
        return status == noErr && running != 0
    }

    // MARK: Property plumbing

    private static func audioAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func cmioAddress(
        _ selector: CMIOObjectPropertySelector
    ) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    /// One fixed-size property, or nil when the object does not carry it.
    ///
    /// initial supplies both the type and a defined value, so nothing reads
    /// uninitialized memory on the failure path.
    private static func audioValue<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        initial: T
    ) -> T? {
        var address = audioAddress(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value : nil
    }

    /// CoreAudio returns a +1 reference stored without a retain; ARC's release
    /// of value at scope exit balances it.
    private static func audioString(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = audioAddress(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else {
            return nil
        }
        return value as String
    }
}
