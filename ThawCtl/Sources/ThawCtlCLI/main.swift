//
//  main.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

// Commands map directly to thaw:// URLs dispatched by AppDelegate.handleURL.
// Keep business logic in the app so GUI, CLI, and Shortcuts share it.

import AppKit

// MARK: - Command table

/// A command's host segment plus the query parameters it accepts.
private struct Command {
    let name: String
    let host: String
    /// Parameters given as key=value arguments, in URL order.
    let valueParams: [String]
    /// Parameters given as bare --flag value.
    let flagParams: [String]
    let usage: String

    /// Settings commands require authorization; this flag only labels help text.
    let needsAuth: Bool

    static let all: [Command] = [
        Command(name: "toggle-hidden", host: "toggle-hidden", valueParams: [], flagParams: [], usage: "thawctl toggle-hidden", needsAuth: false),
        Command(name: "toggle-always-hidden", host: "toggle-always-hidden", valueParams: [], flagParams: [], usage: "thawctl toggle-always-hidden", needsAuth: false),
        Command(name: "search", host: "search", valueParams: [], flagParams: [], usage: "thawctl search", needsAuth: false),
        Command(name: "toggle-thawbar", host: "toggle-thawbar", valueParams: [], flagParams: [], usage: "thawctl toggle-thawbar", needsAuth: false),
        Command(name: "toggle-application-menus", host: "toggle-application-menus", valueParams: [], flagParams: [], usage: "thawctl toggle-application-menus", needsAuth: false),
        Command(name: "toggle-zen-mode", host: "toggle-zen-mode", valueParams: [], flagParams: [], usage: "thawctl toggle-zen-mode", needsAuth: false),
        Command(name: "toggle-layout-editor", host: "toggle-layout-editor", valueParams: [], flagParams: [], usage: "thawctl toggle-layout-editor", needsAuth: false),
        Command(name: "open-settings", host: "open-settings", valueParams: [], flagParams: [], usage: "thawctl open-settings", needsAuth: false),
        Command(name: "dump-items", host: "dump-items", valueParams: [], flagParams: [], usage: "thawctl dump-items", needsAuth: false),
        Command(name: "set", host: "set", valueParams: ["key", "value"], flagParams: ["display"], usage: "thawctl set <key>=<value> [--display <uuid>]", needsAuth: true),
        Command(name: "toggle-setting", host: "toggle", valueParams: ["key"], flagParams: ["display"], usage: "thawctl toggle-setting <key> [--display <uuid>]", needsAuth: true),
        Command(name: "get", host: "get", valueParams: ["key"], flagParams: ["display"], usage: "thawctl get <key> [--display <uuid>]", needsAuth: true),
        Command(name: "authorize", host: "authorize", valueParams: [], flagParams: [], usage: "thawctl authorize", needsAuth: false),
        Command(name: "reveal-item", host: "reveal-item", valueParams: [], flagParams: ["bundle", "item-id"], usage: "thawctl reveal-item (--bundle <id> | --item-id <id>)", needsAuth: true),
    ]
}

// MARK: - Argument parsing

private enum ParseError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case missingValue(command: String, param: String)
    case unexpectedArgument(String)
    case invalidPair(String)

    var description: String {
        switch self {
        case let .unknownCommand(c): "unknown command: \(c)"
        case let .missingValue(command, param): "\(command): missing value for \(param)"
        case let .unexpectedArgument(a): "unexpected argument: \(a)"
        case let .invalidPair(a): "expected key=value, got: \(a)"
        }
    }
}

/// Returns (host, queryItems) or nil when args request help / are empty.
private func parse(_ args: [String]) throws -> (host: String, query: [URLQueryItem])? {
    guard let first = args.first, !first.hasPrefix("-") else { return nil }
    guard let command = Command.all.first(where: { $0.name == first }) else {
        throw ParseError.unknownCommand(first)
    }

    var values: [String: String] = [:]
    var flags: [String: String] = [:]
    var rest = Array(args.dropFirst())

    while let arg = rest.first {
        rest.removeFirst()
        if arg.hasPrefix("--") {
            let name = String(arg.dropFirst(2))
            guard command.flagParams.contains(name) else {
                throw ParseError.unexpectedArgument(arg)
            }
            guard let value = rest.first, !value.hasPrefix("--") else {
                throw ParseError.missingValue(command: command.name, param: name)
            }
            rest.removeFirst()
            flags[name] = value
        } else if arg.contains("=") {
            let pair = arg.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, command.valueParams.contains(pair[0]) else {
                throw ParseError.invalidPair(arg)
            }
            values[pair[0]] = pair[1]
        } else if command.valueParams.count == 1, values[command.valueParams[0]] == nil {
            // Positional shorthand: thawctl get someKey == get key=someKey.
            values[command.valueParams[0]] = arg
        } else {
            throw ParseError.unexpectedArgument(arg)
        }
    }

    for param in command.valueParams where values[param] == nil && flags[param] == nil {
        throw ParseError.missingValue(command: command.name, param: param)
    }

    var query = values.map { URLQueryItem(name: $0.key, value: $0.value) }
    query += flags.filter { command.valueParams.contains($0.key) || $0.key != "wait" }
        .map { URLQueryItem(name: $0.key, value: $0.value) }

    // The CLI writes dumps to disk with no callback handler; only the companion GUI requests thawctl:// responses.
    return (command.host, query.sorted { $0.name < $1.name })
}

// MARK: - Usage

private func printUsage() {
    var out = "Usage: thawctl <command> [args]\n\nCommands:\n"
    for command in Command.all {
        out += "  \(command.usage.padding(toLength: max(command.usage.count + 2, 52), withPad: " ", startingAt: 0))"
        out += command.needsAuth ? "(whitelist)\n" : "\n"
    }
    out += "\nSettings commands require prior authorization: thawctl authorize\n"
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
