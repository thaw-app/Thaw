//
//  AXWire.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Darwin
import Foundation

/// Framing over a byte stream: a 4-byte big-endian length, then that many bytes
/// of JSON. One request, one reply. XPC replaces only this file.
public enum AXWire {
    /// Cap so a corrupt length cannot ask for an unbounded allocation.
    public static let maximumFrameBytes = 16 * 1024 * 1024

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public enum WireError: Error, CustomStringConvertible, Equatable {
        case tooLarge(Int)
        case truncated
        case empty
        case timedOut
        case encode(String)
        case decode(String)

        public var description: String {
            switch self {
            case let .tooLarge(size): "AX frame too large (\(size) bytes)"
            case .truncated: "AX frame truncated"
            case .empty: "AX frame was empty"
            case .timedOut: "AX frame read timed out"
            case let .encode(reason): "AX frame encode failed: \(reason)"
            case let .decode(reason): "AX frame decode failed: \(reason)"
            }
        }
    }

    public static func encode(_ value: some Encodable) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw WireError.encode(String(describing: error))
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw WireError.decode(String(describing: error))
        }
    }

    /// Writes value as one frame.
    public static func write(_ value: some Encodable, to handle: FileHandle) throws {
        let payload = try encode(value)
        var length = UInt32(payload.count).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: payload)
    }

    /// Reads and decodes one frame, or nil at a clean end of stream.
    ///
    /// timeoutSeconds bounds the wait for each chunk. Without it a helper that
    /// wedges outside an AX call parks the reader on a blocking pipe read with
    /// no way out; with it the read throws WireError.timedOut and the caller
    /// can kill and relaunch the helper.
    public static func read<T: Decodable>(
        _ type: T.Type,
        from handle: FileHandle,
        timeoutSeconds: Double? = nil
    ) throws -> T? {
        let deadline = timeoutSeconds.map { Date().addingTimeInterval($0) }
        guard let header = try readExactly(4, from: handle, deadline: deadline) else { return nil }
        guard header.count == 4 else { throw WireError.truncated }
        let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let size = Int(length)
        guard size > 0 else { throw WireError.empty }
        guard size <= maximumFrameBytes else { throw WireError.tooLarge(size) }
        guard let payload = try readExactly(size, from: handle, deadline: deadline) else {
            throw WireError.truncated
        }
        return try decode(type, from: payload)
    }

    private static func readExactly(_ count: Int, from handle: FileHandle, deadline: Date?) throws -> Data? {
        var buffer = Data()
        buffer.reserveCapacity(count)
        while buffer.count < count {
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw WireError.timedOut }
                try waitForReadable(handle, timeoutSeconds: remaining)
            }
            guard let chunk = try handle.read(upToCount: count - buffer.count), !chunk.isEmpty else {
                return buffer.isEmpty ? nil : buffer
            }
            buffer.append(chunk)
        }
        return buffer
    }

    /// Blocks until the descriptor is readable or the timeout elapses.
    private static func waitForReadable(_ handle: FileHandle, timeoutSeconds: Double) throws {
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let milliseconds = Int32(min(max(timeoutSeconds, 0.001), 60) * 1000)
        while true {
            let result = poll(&descriptor, 1, milliseconds)
            if result == 0 {
                throw WireError.timedOut
            }
            if result < 0 {
                if errno == EINTR {
                    continue
                }
                throw WireError.timedOut
            }
            return
        }
    }
}
