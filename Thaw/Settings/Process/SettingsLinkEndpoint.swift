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

    private let onMessage: @MainActor (SettingsLinkMessage) -> Void
    private let onClose: @MainActor () -> Void

    /// Calls onMessage for each message read, and onClose once the other end has closed the pipe.
    init(
        input: FileHandle,
        output: FileHandle,
        onMessage: @escaping @MainActor (SettingsLinkMessage) -> Void,
        onClose: @escaping @MainActor () -> Void = {
            // Most ends have nothing to do when the other end goes.
        }
    ) {
        self.input = input
        self.output = output
        self.onMessage = onMessage
        self.onClose = onClose
        // A write after the other end has gone then fails with EPIPE instead of killing this process.
        _ = fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1)
        // Not input.bytes.lines: Foundation reads every AsyncBytes in a process on one serial
        // queue with a blocking read, so this pipe, open as long as Settings is, would stall the rest.
        input.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // At the end of the pipe the handler keeps firing with nothing read until it is removed.
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            Self.deliver(data, to: self)
        }
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .filter { [weak self] _ in self?.isReloading == false }
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.send(.settingsChanged) }
    }

    /// The main queue keeps the chunks in the order they were read.
    private nonisolated static func deliver(_ data: Data, to endpoint: SettingsLinkEndpoint?) {
        DispatchQueue.main.async { [weak endpoint] in
            MainActor.assumeIsolated { endpoint?.received(data) }
        }
    }

    private func received(_ data: Data) {
        guard !isClosed else { return }
        if data.isEmpty {
            close()
            onClose()
        } else {
            read(data).forEach(onMessage)
        }
    }

    /// A failed write means the other end has gone, so nothing more is sent.
    func send(_ message: SettingsLinkMessage) {
        guard !isClosed else { return }
        do {
            try output.write(contentsOf: message.line)
        } catch {
            close()
        }
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
