//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// Commands map directly to thaw:// URLs dispatched by AppDelegate.handleURL.
// Keep business logic in the app so GUI, CLI, and Shortcuts share it.

import AppKit

// MARK: - Usage

private func printUsage() {
    var out = "Usage: thawctl <command> [args]\n\nCommands:\n"
    for command in Command.all {
        out += "  \(command.usage.padding(toLength: max(command.usage.count + 2, 52), withPad: " ", startingAt: 0))"
        out += command.needsAuth ? "(whitelist)\n" : "\n"
    }
    out += "\nSettings commands require prior authorization: thawctl authorize\n"
    out += "Reading settings needs an app that receives Thaw's callback, such as ThawCtl.\n"
    FileHandle.standardError.write(Data(out.utf8))
}

// MARK: - Entry point

let status: Int32
do {
    guard let parsed = try parse(Array(CommandLine.arguments.dropFirst())) else {
        printUsage()
        exit(64) // Usage error.
    }

    var components = URLComponents()
    components.scheme = "thaw"
    components.host = parsed.host
    if !parsed.query.isEmpty {
        components.queryItems = parsed.query
    }
    guard let url = components.url else {
        FileHandle.standardError.write(Data("thawctl: failed to build URL\n".utf8))
        exit(70) // Software error.
    }

    // Success means LaunchServices accepted the URL, not that the action took effect; no delivery confirmation.
    let opened = NSWorkspace.shared.open(url)
    print(opened ? "sent: \(url.absoluteString)" : "undeliverable: \(url.absoluteString)")
    status = opened ? 0 : 1
} catch let error as ParseError {
    FileHandle.standardError.write(Data("thawctl: \(error)\n\n".utf8))
    printUsage()
    status = 64
}

exit(status)
