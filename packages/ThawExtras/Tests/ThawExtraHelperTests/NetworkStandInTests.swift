//
//  NetworkStandInTests.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import IOBluetooth
import Testing
@testable import ThawExtraHelper

@Suite("Wi-Fi and Bluetooth stand-ins")
struct NetworkStandInTests {
    private func wiFi(on: Bool = true, rssi: Int, rate: Double = 400) -> WiFiReading {
        WiFiReading(interfaceName: "en0", isPoweredOn: on, rssi: rssi, transmitRate: rate)
    }

    @Test("Signal bars drop at -60 and -70 dBm, and show none while not associated")
    func signalBars() {
        #expect(wiFi(rssi: -50).signalLevel == 1)
        #expect(wiFi(rssi: -60).signalLevel == 1)
        #expect(wiFi(rssi: -65).signalLevel == 0.66)
        #expect(wiFi(rssi: -80).signalLevel == 0.33)
        #expect(wiFi(rssi: 0, rate: 0).signalLevel == 0)
        #expect(!wiFi(on: false, rssi: -50).isConnected)
        #expect(wiFi(on: false, rssi: 0).symbolName == "wifi.slash")
    }

    @Test("The router is offered only while Wi-Fi carries the default route")
    func routerFollowsPrimaryInterface() {
        let interface = ["Addresses": ["192.168.1.23"]]
        let global: [String: Any] = ["PrimaryInterface": "en0", "Router": "192.168.1.1"]
        #expect(NetworkAddresses(interfaceState: interface, globalState: global, interface: "en0")
            == NetworkAddresses(address: "192.168.1.23", router: "192.168.1.1"))
        #expect(NetworkAddresses(interfaceState: interface, globalState: global, interface: "en1")
            == NetworkAddresses(address: "192.168.1.23", router: nil))
    }

    @Test("networkQuality's JSON reads as whole megabits per second, and anything else as no result")
    func speedTestOutput() {
        let json = Data(#"{"dl_throughput": 412345678, "ul_throughput": 38499999, "base_rtt": 12}"#.utf8)
        #expect(ConnectionSpeedTest.parse(json) == .init(download: 412, upload: 38))
        #expect(ConnectionSpeedTest.parse(Data("error".utf8)) == nil)
    }

    @Test("Connected devices come first, then the rest by name")
    func deviceOrder() {
        func row(_ name: String, _ connected: Bool) -> BluetoothDeviceRow {
            BluetoothDeviceRow(address: name, name: name, isConnected: connected, symbolName: "")
        }
        let sorted = BluetoothReading.sorted([row("Mouse", false), row("Keyboard", false), row("AirPods", true)])
        #expect(sorted.map(\.name) == ["AirPods", "Keyboard", "Mouse"])
    }

    @Test("Each device class gets its own symbol")
    func deviceSymbols() {
        let audio = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio)
        let peripheral = BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral)
        #expect(BluetoothReading.symbolName(major: audio, minor: 0) == "headphones")
        #expect(BluetoothReading.symbolName(major: peripheral, minor: 0x10) == "keyboard")
        #expect(BluetoothReading.symbolName(major: peripheral, minor: 0x20) == "computermouse")
        #expect(BluetoothReading.symbolName(major: 0x1F, minor: 0) == "dot.radiowaves.left.and.right")
    }
}
