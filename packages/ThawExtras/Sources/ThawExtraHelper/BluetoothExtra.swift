//
//  BluetoothExtra.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import IOBluetooth
import OSLog

/// IOBluetooth blocks on the permission prompt and while it connects, so every
/// call runs off the main thread and the menu shows the last reading.
@MainActor
final class BluetoothExtra: NSObject, MenuActionTarget {
    private let button: NSStatusBarButton
    private let label: String
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThawExtraHelper", category: "bluetooth")
    private var reading = BluetoothReading(isPoweredOn: true, devices: [])
    private var busyAddresses: Set<String> = []
    /// The menu last opened, refilled when a reading lands while it is still up.
    private weak var openMenu: NSMenu?
    private var pollTask: Task<Void, Never>?

    init(button: NSStatusBarButton, label: String) {
        self.button = button
        self.label = label
        super.init()
    }

    func start() {
        button.image = PrivateSymbolGlyph.bluetooth(accessibilityDescription: label)
        button.toolTip = label
        // Bluetooth posts no power change short of registering per device, so poll.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
    }

    func populate(_ menu: NSMenu) {
        openMenu = menu
        Task { await refresh() }
        fill(menu)
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(actionItem(
            reading.isPoweredOn ? String(localized: "Turn Bluetooth Off") : String(localized: "Turn Bluetooth On"),
            #selector(togglePower)
        ))
        if reading.isPoweredOn {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: String(localized: "Devices")))
            if reading.devices.isEmpty {
                menu.addItem(.info(String(localized: "No Devices")))
            }
            for device in reading.devices {
                let busy = busyAddresses.contains(device.address)
                let title = busy
                    ? (device.isConnected ? String(localized: "\(device.name) (Disconnecting…)") : String(localized: "\(device.name) (Connecting…)"))
                    : device.name
                let item = actionItem(title, #selector(toggleConnection(_:)))
                item.representedObject = device.address
                item.state = device.isConnected ? .on : .off
                item.image = NSImage(systemSymbolName: device.symbolName, accessibilityDescription: nil)
                item.isEnabled = !busy
                item.toolTip = device.isConnected ? String(localized: "Click to disconnect") : String(localized: "Click to connect")
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Bluetooth Settings…"), #selector(openSettings)))
    }

    // MARK: Reading

    private func refresh() async {
        let fresh = await Task.detached { BluetoothReading.current() }.value
        guard fresh != reading else { return }
        reading = fresh
        button.appearsDisabled = !fresh.isPoweredOn
        if let openMenu {
            fill(openMenu)
        }
    }

    // MARK: Actions

    @objc private func togglePower() {
        let on = !reading.isPoweredOn
        Task {
            await Task.detached { BluetoothPower.set(on) }.value
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }
    }

    @objc private func toggleConnection(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String,
              let device = reading.devices.first(where: { $0.address == address }),
              busyAddresses.insert(address).inserted
        else { return }
        let connect = !device.isConnected
        Task {
            let status = await Task.detached { BluetoothReading.setConnected(connect, address: address) }.value
            if status != kIOReturnSuccess {
                logger.error("Bluetooth \(connect ? "connect" : "disconnect", privacy: .public) failed: \(status)")
            }
            busyAddresses.remove(address)
            await refresh()
        }
    }

    @objc private func openSettings() {
        SystemSettings.open("com.apple.BluetoothSettings")
    }
}

// MARK: - Reading

struct BluetoothDeviceRow: Equatable, Sendable {
    var address: String
    var name: String
    var isConnected: Bool
    var symbolName: String
}

struct BluetoothReading: Equatable, Sendable {
    var isPoweredOn: Bool
    var devices: [BluetoothDeviceRow]

    /// Blocks while the permission prompt is up; never call it on the main thread.
    nonisolated static func current() -> BluetoothReading {
        let isPoweredOn = BluetoothPower.isOn()
        guard isPoweredOn else { return BluetoothReading(isPoweredOn: false, devices: []) }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let rows = paired.compactMap { device -> BluetoothDeviceRow? in
            guard let address = device.addressString else { return nil }
            return BluetoothDeviceRow(
                address: address,
                name: device.nameOrAddress ?? address,
                isConnected: device.isConnected(),
                symbolName: symbolName(major: device.deviceClassMajor, minor: device.deviceClassMinor)
            )
        }
        return BluetoothReading(isPoweredOn: true, devices: sorted(rows))
    }

    /// Connected devices first, then by name.
    nonisolated static func sorted(_ rows: [BluetoothDeviceRow]) -> [BluetoothDeviceRow] {
        rows.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    nonisolated static func setConnected(_ connect: Bool, address: String) -> IOReturn {
        guard let device = IOBluetoothDevice(addressString: address) else { return kIOReturnNotFound }
        return connect ? device.openConnection() : device.closeConnection()
    }

    nonisolated static func symbolName(major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> String {
        switch Int(major) {
        case kBluetoothDeviceClassMajorAudio: "headphones"
        case kBluetoothDeviceClassMajorPeripheral:
            // The peripheral minor class keeps keyboard and pointer in its top two bits.
            minor & 0x10 != 0 ? "keyboard" : "computermouse"
        case kBluetoothDeviceClassMajorPhone: "iphone"
        case kBluetoothDeviceClassMajorComputer: "laptopcomputer"
        default: "dot.radiowaves.left.and.right"
        }
    }
}

/// Bluetooth's power switch is private IOBluetooth API, the pair blueutil calls.
enum BluetoothPower {
    private typealias Get = @convention(c) () -> Int32
    private typealias SetPower = @convention(c) (Int32) -> Void

    nonisolated static func isOn() -> Bool {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOBluetoothPreferenceGetControllerPowerState") else {
            return true
        }
        return unsafeBitCast(symbol, to: Get.self)() != 0
    }

    nonisolated static func set(_ on: Bool) {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOBluetoothPreferenceSetControllerPowerState") else {
            return
        }
        unsafeBitCast(symbol, to: SetPower.self)(on ? 1 : 0)
    }
}
