//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation
import Synchronization
import ThawAXCore

// The AX helper's serving loop. Frames are tagged, so requests are answered
// out of order: this thread only reads and routes, each lane answers on its
// own thread, and replies share one locked writer. Runs until stdin closes.
// Accessibility permission is the helper's own; every reply reports it.

let input = FileHandle.standardInput
let output = FileHandle.standardOutput
let writeLock = NSLock()
let writerFailed = Atomic<Bool>(false)

let scheduler = AXLaneScheduler(
    serve: { AXReader.serve($0) },
    emit: { frame in
        writeLock.lock()
        defer { writeLock.unlock() }
        do {
            try AXWire.write(frame, to: output)
        } catch {
            // The app has gone; nothing left to answer.
            if writerFailed.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged {
                FileHandle.standardError.write(Data("ThawAXHelper: failed to write reply: \(error)\n".utf8))
                exit(0)
            }
        }
    }
)

// Each read gets its own pool: this loop never returns to a run loop.
while autoreleasepool(invoking: { () -> Bool in
    let frame: AXRequestFrame
    do {
        guard let decoded = try AXWire.read(AXRequestFrame.self, from: input) else {
            return false
        }
        frame = decoded
    } catch {
        FileHandle.standardError.write(Data("ThawAXHelper: bad request frame: \(error)\n".utf8))
        return false
    }
    scheduler.submit(frame)
    return true
}) {}

// stdin closed. Answer what is already queued before leaving: the app may
// have closed its end of the request pipe while still reading replies.
scheduler.closeAndDrain()
exit(0)
