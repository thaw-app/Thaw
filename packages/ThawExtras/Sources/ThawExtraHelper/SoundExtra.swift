//
//  SoundExtra.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import AudioToolbox
import CoreAudio

/// The Sound stand-in: output volume and mute, and the output and input
/// devices to pick from. CoreAudio needs no permission for any of it.
@MainActor
final class SoundExtra: NSObject {
    private let button: NSStatusBarButton
    private let label: String
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var watchedOutput: AudioObjectID = kAudioObjectUnknown

    init(button: NSStatusBarButton, label: String) {
        self.button = button
        self.label = label
        super.init()
    }

    func start() {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            listen(AudioObjectID(kAudioObjectSystemObject), selector, scope: kAudioObjectPropertyScopeGlobal)
        }
        watchOutput()
        refreshIcon()
    }

    func stop() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
    }

    func populate(_ menu: NSMenu) {
        let output = AudioDevices.defaultDevice(input: false)
        if let output, let volume = AudioDevices.volume(of: output) {
            menu.addItem(.sectionHeader(title: String(localized: "Output Volume")))
            menu.addItem(sliderItem(volume: volume, device: output))
            let mute = actionItem(String(localized: "Mute"), #selector(toggleMute))
            mute.state = AudioDevices.isMuted(output) ? .on : .off
            menu.addItem(mute)
            menu.addItem(.separator())
        }
        let devices = AudioDevices.all()
        addDevices(devices.filter(\.hasOutput), title: String(localized: "Output"), current: output, input: false, to: menu)
        menu.addItem(.separator())
        let input = AudioDevices.defaultDevice(input: true)
        addDevices(devices.filter(\.hasInput), title: String(localized: "Input"), current: input, input: true, to: menu)
        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Sound Settings…"), #selector(openSettings)))
    }

    // MARK: Menu

    private func addDevices(_ devices: [AudioDevice], title: String, current: AudioObjectID?, input: Bool, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: title))
        for device in devices {
            let item = actionItem(device.name, input ? #selector(selectInput(_:)) : #selector(selectOutput(_:)))
            item.representedObject = device.id
            item.state = device.id == current ? .on : .off
            menu.addItem(item)
        }
    }

    private func sliderItem(volume: Float, device: AudioObjectID) -> NSMenuItem {
        let slider = NSSlider(value: Double(volume), minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged(_:)))
        slider.isContinuous = true
        slider.setAccessibilityLabel(String(localized: "Output Volume"))
        slider.frame = NSRect(x: 18, y: 2, width: 200, height: 22)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 236, height: 26))
        container.addSubview(slider)
        let item = NSMenuItem()
        item.view = container
        return item
    }

    // MARK: Icon

    private func refreshIcon() {
        let output = AudioDevices.defaultDevice(input: false)
        let volume = output.flatMap(AudioDevices.volume(of:)) ?? 1
        let muted = output.map(AudioDevices.isMuted) ?? false
        let image = NSImage(
            systemSymbolName: AudioDevices.symbolName(muted: muted, volume: volume),
            variableValue: Double(volume),
            accessibilityDescription: label
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = label
    }

    // MARK: Listening

    /// The volume and mute listeners follow the default output device.
    private func watchOutput() {
        let output = AudioDevices.defaultDevice(input: false) ?? kAudioObjectUnknown
        guard output != watchedOutput else { return }
        listeners.removeAll { entry in
            guard entry.0 == watchedOutput else { return false }
            var address = entry.1
            AudioObjectRemovePropertyListenerBlock(entry.0, &address, .main, entry.2)
            return true
        }
        watchedOutput = output
        guard output != kAudioObjectUnknown else { return }
        listen(output, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        listen(output, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.watchOutput()
                self?.refreshIcon()
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    // MARK: Actions

    @objc private func volumeChanged(_ sender: NSSlider) {
        guard let output = AudioDevices.defaultDevice(input: false) else { return }
        AudioDevices.setVolume(Float(sender.doubleValue), of: output)
    }

    @objc private func toggleMute() {
        guard let output = AudioDevices.defaultDevice(input: false) else { return }
        AudioDevices.setMuted(!AudioDevices.isMuted(output), of: output)
    }

    @objc private func selectOutput(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioObjectID else { return }
        AudioDevices.setDefaultDevice(id, input: false)
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioObjectID else { return }
        AudioDevices.setDefaultDevice(id, input: true)
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

// MARK: - CoreAudio

struct AudioDevice: Equatable {
    var id: AudioObjectID
    var name: String
    var hasOutput: Bool
    var hasInput: Bool
}

enum AudioDevices {
    static func all() -> [AudioDevice] {
        let ids: [AudioObjectID] = array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        return ids.compactMap { id in
            guard let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioDevice(
                id: id,
                name: name,
                hasOutput: streamCount(id, scope: kAudioDevicePropertyScopeOutput) > 0,
                hasInput: streamCount(id, scope: kAudioDevicePropertyScopeInput) > 0
            )
        }
    }

    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        let id: AudioObjectID? = value(AudioObjectID(kAudioObjectSystemObject), selector)
        return id == kAudioObjectUnknown ? nil : id
    }

    static func setDefaultDevice(_ id: AudioObjectID, input: Bool) {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        set(id, on: AudioObjectID(kAudioObjectSystemObject), selector)
    }

    /// Nil when the device has no volume to set, as with HDMI and many USB devices.
    static func volume(of device: AudioObjectID) -> Float? {
        value(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    }

    static func setVolume(_ volume: Float, of device: AudioObjectID) {
        set(min(max(volume, 0), 1), on: device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    }

    static func isMuted(_ device: AudioObjectID) -> Bool {
        let muted: UInt32? = value(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        return muted == 1
    }

    static func setMuted(_ muted: Bool, of device: AudioObjectID) {
        set(UInt32(muted ? 1 : 0), on: device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }

    /// The waves follow the volume through the symbol's variable value.
    static func symbolName(muted: Bool, volume: Float) -> String {
        muted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }

    // MARK: Property access

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    private static func set<T>(_ value: T, on object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) {
        var address = address(selector, scope)
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue else { return }
        var value = value
        AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }

    private static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [T] {
        var address = address(selector, kAudioObjectPropertyScopeGlobal)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector, kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func streamCount(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }
}
