//
//  QuitRequestSource.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import AppKit

/// Says who asked Thaw to quit, for the log.
///
/// Another app, a script or loginwindow asks through a quit Apple event,
/// which carries the sender's process and, for a logout, restart or
/// shutdown, a reason. A quit from Thaw's own menu or ⌘Q has no such event.
nonisolated enum QuitRequestSource {
    /// The sender of the quit event being handled now, read from the event.
    @MainActor
    static func current() -> String {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isQuit = event?.eventClass == fourCharCode("aevt") && event?.eventID == fourCharCode("quit")
        let senderPID = isQuit
            ? event?.attributeDescriptor(forKeyword: fourCharCode("spid"))?.int32Value
            : nil
        let reason = isQuit ? event?.paramDescriptor(forKeyword: fourCharCode("why?"))?.enumCodeValue : nil
        let senderName = senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
        return describe(senderPID: senderPID, senderName: senderName, reason: reason, ownPID: getpid())
    }

    static func describe(senderPID: pid_t?, senderName: String?, reason: OSType?, ownPID: pid_t) -> String {
        guard let senderPID, senderPID != ownPID else { return "from Thaw itself" }
        let sender = senderName.map { "\($0) (pid \(senderPID))" } ?? "pid \(senderPID)"
        let because = reason.map { ", reason \(string(fromFourCharCode: $0))" } ?? ""
        return "by \(sender)\(because)"
    }

    static func fourCharCode(_ code: String) -> OSType {
        code.utf8.reduce(0) { $0 << 8 | OSType($1) }
    }

    static func string(fromFourCharCode code: OSType) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .macOSRoman) ?? "\(code)"
    }
}
