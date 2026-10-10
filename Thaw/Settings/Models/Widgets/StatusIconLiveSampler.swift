//
//  StatusIconLiveSampler.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation
import Network

/// Polls real system readings and publishes them as StatusIconSamples.
///
/// Uses Barometer's optimized sources (CPUSource, WiFiSource, BatteryLevelSource)
/// with credit. Volume is left at the slider value, it needs a CoreAudio
/// callback, not a poll, and the prototype's manual control stays for it.
@MainActor
final class StatusIconLiveSampler: ObservableObject {
    @Published private(set) var samples = StatusIconSamples(network: .unknown)

    private var timer: Timer?
    private var networkTask: Task<Void, Never>?
    private let cpuSource = CPUSource()
    private let wifiSource = WiFiSource()
    private var previousCpuTicks: (user: UInt64, system: UInt64, total: UInt64) = (0, 0, 0)

    func start() {
        guard timer == nil else { return }
        samples.network = .unknown
        networkTask = Task { [weak self] in
            for await path in NWPathMonitor() {
                guard !Task.isCancelled, let self else { return }
                // availableInterfaces includes idle radios. Only interfaces
                // actually used by the default path describe this connection.
                samples.network = StatusIconNetwork(
                    status: path.status,
                    usedInterfaces: [.wiredEthernet, .wifi, .cellular, .other].filter { path.usesInterfaceType($0) }
                )
                samples.wifi = wifiStrength()
            }
        }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        networkTask?.cancel()
        networkTask = nil
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        samples.battery = BatteryLevelSource.level()
        samples.wifi = wifiStrength()
        samples.cpu = cpuUsage()
    }

    // MARK: Wi-Fi

    private func wifiStrength() -> Double {
        guard let snapshot = wifiSource.read(),
              let rssi = snapshot.rssi else { return 0 }
        let normalized = Double(rssi + 100) / 70.0
        return normalized.clamped(to: 0 ... 1)
    }

    // MARK: CPU

    private func cpuUsage() -> Double {
        guard let snapshot = try? cpuSource.readTicks() else { return 0 }
        let user = snapshot.cores.reduce(0) { $0 + $1.user }
        let system = snapshot.cores.reduce(0) { $0 + $1.system }
        let idle = snapshot.cores.reduce(0) { $0 + $1.idle }
        let total = user + system + idle
        guard total > previousCpuTicks.total else {
            previousCpuTicks = (user, system, total)
            return samples.cpu
        }
        let deltaUser = user &- previousCpuTicks.user
        let deltaSystem = system &- previousCpuTicks.system
        let deltaTotal = total &- previousCpuTicks.total
        previousCpuTicks = (user, system, total)
        guard deltaTotal > 0 else { return 0 }
        return Double(deltaUser + deltaSystem) / Double(deltaTotal)
    }
}
