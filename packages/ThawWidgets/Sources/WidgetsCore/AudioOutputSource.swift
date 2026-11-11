//
//  AudioOutputSource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import CoreAudio
import Foundation

/// Reads the default audio output from CoreAudio. Property reads need no permission or entitlement.
enum AudioOutputSource {
    static let bluetoothTransport = kAudioDeviceTransportTypeBluetooth
    static let bluetoothLETransport = kAudioDeviceTransportTypeBluetoothLE

    /// The output for a device's name and transport, or nil without a name.
    static func output(name: String?, transport: UInt32) -> StatusIconAudioOutput? {
        guard let name, !name.isEmpty else { return nil }
        let isBluetooth = transport == bluetoothTransport || transport == bluetoothLETransport
        return StatusIconAudioOutput(name: name, isBluetooth: isBluetooth)
    }

    /// The system's default output now, or nil when CoreAudio has none.
    static func defaultOutput() -> StatusIconAudioOutput? {
        var device = AudioObjectID(kAudioObjectUnknown)
        guard read(kAudioHardwarePropertyDefaultOutputDevice, of: AudioObjectID(kAudioObjectSystemObject), into: &device), device != kAudioObjectUnknown
        else { return nil }
        var transport: UInt32 = 0
        // A device whose transport can't be read counts as not Bluetooth.
        _ = read(kAudioDevicePropertyTransportType, of: device, into: &transport)
        var name: Unmanaged<CFString>?
        guard read(kAudioObjectPropertyName, of: device, into: &name) else { return nil }
        return output(name: name?.takeRetainedValue() as String?, transport: transport)
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }
}
