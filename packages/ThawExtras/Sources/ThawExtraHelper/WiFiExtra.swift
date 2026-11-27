//
//  WiFiExtra.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit
import CoreWLAN
import OSLog

/// Nothing here needs Location access, so the network name and nearby networks
/// stay in Control Center.
@MainActor
final class WiFiExtra: NSObject, MenuActionTarget {
    private let button: NSStatusBarButton
    private let label: String
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ThawExtraHelper", category: "wifi")
    private let events = WiFiEvents()
    private var speedTest = ConnectionSpeedTest.State.idle

    init(button: NSStatusBarButton, label: String) {
        self.button = button
        self.label = label
        super.init()
    }

    func start() {
        events.onChange = { [weak self] in
            Task { @MainActor in self?.refreshIcon() }
        }
        events.start()
        refreshIcon()
    }

    func stop() {
        events.stop()
    }

    func populate(_ menu: NSMenu) {
        let reading = WiFiReading.current()
        menu.addItem(actionItem(
            reading.isPoweredOn ? String(localized: "Turn Wi-Fi Off") : String(localized: "Turn Wi-Fi On"),
            #selector(togglePower)
        ))
        if reading.isPoweredOn {
            menu.addItem(.separator())
            if reading.isConnected {
                for line in reading.detailLines {
                    menu.addItem(NSMenuItem.info(line))
                }
            } else {
                menu.addItem(NSMenuItem.info(String(localized: "Not connected")))
            }
            let addresses = NetworkAddresses.current(interface: reading.interfaceName)
            if let address = addresses.address {
                let item = actionItem(String(localized: "Copy IP Address (\(address))"), #selector(copyText(_:)))
                item.representedObject = address
                menu.addItem(item)
            }
            if let router = addresses.router {
                let item = actionItem(String(localized: "Open Router Page (\(router))"), #selector(openRouter(_:)))
                item.representedObject = router
                menu.addItem(item)
            }
            menu.addItem(.separator())
            addSpeedTest(to: menu, connected: reading.isConnected)
        }
        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Wi-Fi Settings…"), #selector(openSettings)))
    }

    // MARK: Icon

    private func refreshIcon() {
        let reading = WiFiReading.current()
        let image = NSImage(
            systemSymbolName: reading.symbolName,
            variableValue: reading.signalLevel,
            accessibilityDescription: label
        )
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !reading.isConnected
        button.toolTip = label
    }

    // MARK: Speed test

    private func addSpeedTest(to menu: NSMenu, connected: Bool) {
        switch speedTest {
        case .running:
            let item = NSMenuItem.info(String(localized: "Testing Connection Speed…"))
            menu.addItem(item)
        case let .finished(result):
            menu.addItem(NSMenuItem.info(result.summary))
            fallthrough
        case .idle, .failed:
            let item = actionItem(String(localized: "Test Connection Speed"), #selector(runSpeedTest))
            item.isEnabled = connected
            menu.addItem(item)
        }
        if case .failed = speedTest {
            menu.addItem(NSMenuItem.info(String(localized: "The last speed test didn’t finish.")))
        }
    }

    @objc private func runSpeedTest() {
        guard speedTest != .running else { return }
        speedTest = .running
        Task { [weak self] in
            let result = await ConnectionSpeedTest.run()
            self?.speedTest = result.map(ConnectionSpeedTest.State.finished) ?? .failed
        }
    }

    // MARK: Actions

    @objc private func togglePower() {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        do {
            try interface.setPower(!interface.powerOn())
        } catch {
            logger.error("Wi-Fi power change failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshIcon()
    }

    @objc private func copyText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openRouter(_ sender: NSMenuItem) {
        guard let router = sender.representedObject as? String, let url = URL(string: "http://\(router)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSettings() {
        SystemSettings.open("com.apple.wifi-settings-extension")
    }
}

// MARK: - Reading

/// One look at the Wi-Fi interface, without the network name.
struct WiFiReading: Equatable {
    var interfaceName: String?
    var isPoweredOn: Bool
    /// dBm; 0 when not associated.
    var rssi: Int
    /// Mbps; 0 when not associated.
    var transmitRate: Double
    var band: String?

    var isConnected: Bool {
        isPoweredOn && rssi != 0 && transmitRate > 0
    }

    var symbolName: String {
        isPoweredOn ? "wifi" : "wifi.slash"
    }

    var signalLevel: Double {
        guard isConnected else { return 0 }
        if rssi >= -60 { return 1 }
        return rssi >= -70 ? 0.66 : 0.33
    }

    var detailLines: [String] {
        var lines = [String(localized: "Signal \(rssi) dBm")]
        let speed = String(localized: "Link speed \(Int(transmitRate.rounded())) Mbps")
        lines.append(band.map { "\(speed) · \($0)" } ?? speed)
        return lines
    }

    static func current() -> WiFiReading {
        guard let interface = CWWiFiClient.shared().interface() else {
            return WiFiReading(interfaceName: nil, isPoweredOn: false, rssi: 0, transmitRate: 0)
        }
        return WiFiReading(
            interfaceName: interface.interfaceName,
            isPoweredOn: interface.powerOn(),
            rssi: interface.rssiValue(),
            transmitRate: interface.transmitRate(),
            band: interface.wlanChannel().flatMap { bandName($0.channelBand) }
        )
    }

    static func bandName(_ band: CWChannelBand) -> String? {
        switch band {
        case .band2GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: nil
        }
    }
}

// MARK: - Events

/// CoreWLAN calls its delegate on a queue of its own.
private final class WiFiEvents: NSObject, CWEventDelegate, @unchecked Sendable {
    var onChange: (@Sendable () -> Void)?
    private let client = CWWiFiClient.shared()

    func start() {
        client.delegate = self
        for event: CWEventType in [.powerDidChange, .linkDidChange, .linkQualityDidChange] {
            try? client.startMonitoringEvent(with: event)
        }
    }

    func stop() {
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
    }

    func powerStateDidChangeForWiFiInterface(withName _: String) {
        onChange?()
    }

    func linkDidChangeForWiFiInterface(withName _: String) {
        onChange?()
    }

    func linkQualityDidChangeForWiFiInterface(withName _: String, rssi _: Int, transmitRate _: Double) {
        onChange?()
    }
}
