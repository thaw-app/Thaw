//
//  SettingsLinkEndpoint.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Combine
import Foundation

/// One end of the pipe between the app and its settings process. It also tells the other end
/// when this process writes settings, except while it reads the other end's.
@MainActor
final class SettingsLinkEndpoint {
    private let input: FileHandle
    private let output: FileHandle
    private var unreadLine = Data()
    private var defaultsObserver: AnyCancellable?
    private var isReloading = false
    private var isClosed = false

    /// Calls onMessage for each message read, and onClose once the other end has closed the pipe.
    init(
        input: FileHandle,
        output: FileHandle,
        onMessage: @escaping @MainActor (SettingsLinkMessage) -> Void,
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        self.input = input
        self.output = output
        // Not input.bytes.lines: Foundation reads every AsyncBytes in a process on one serial
        // queue with a blocking read, so this pipe, open as long as Settings is, would stall the rest.
        input.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // At the end of the pipe the handler keeps firing with nothing read until it is removed.
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            // The main queue keeps the chunks in the order they were read.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.isClosed else { return }
                    if data.isEmpty {
                        self.close()
                        onClose()
                    } else {
                        self.read(data).forEach(onMessage)
                    }
                }
            }
        }
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .filter { [weak self] _ in self?.isReloading == false }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.send(.settingsChanged) }
    }

    func send(_ message: SettingsLinkMessage) {
        try? output.write(contentsOf: message.line)
    }

    /// Runs body without telling the other end about the settings it writes.
    func reloading(_ body: () -> Void) {
        isReloading = true
        body()
        isReloading = false
    }

    func close() {
        isClosed = true
        input.readabilityHandler = nil
        defaultsObserver = nil
    }

    /// The messages in the complete lines read so far. A line split across reads waits for its end.
    private func read(_ data: Data) -> [SettingsLinkMessage] {
        unreadLine.append(data)
        var messages = [SettingsLinkMessage]()
        while let newline = unreadLine.firstIndex(of: 0x0A) {
            let line = Data(unreadLine[unreadLine.startIndex ..< newline])
            unreadLine.removeSubrange(unreadLine.startIndex ... newline)
            if let message = SettingsLinkMessage(line: line) {
                messages.append(message)
            }
        }
        return messages
    }
}
