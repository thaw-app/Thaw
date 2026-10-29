//
//  Parsing.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Foundation

// MARK: - Command table

/// A command's host segment plus the query parameters it accepts.
struct Command {
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
        Command(name: "toggle-thawbar", host: "toggle-thawbar", valueParams: [], flagParams: [], usage: "thawctl toggle-thawbar", needsAuth: true),
        Command(name: "toggle-application-menus", host: "toggle-application-menus", valueParams: [], flagParams: [], usage: "thawctl toggle-application-menus", needsAuth: false),
        Command(name: "toggle-zen-mode", host: "toggle-zen-mode", valueParams: [], flagParams: [], usage: "thawctl toggle-zen-mode", needsAuth: false),
        Command(name: "toggle-layout-editor", host: "toggle-layout-editor", valueParams: [], flagParams: [], usage: "thawctl toggle-layout-editor", needsAuth: false),
        Command(name: "open-settings", host: "open-settings", valueParams: [], flagParams: [], usage: "thawctl open-settings", needsAuth: false),
        Command(name: "dump-items", host: "dump-items", valueParams: [], flagParams: [], usage: "thawctl dump-items", needsAuth: true),
        Command(name: "set", host: "set", valueParams: ["key", "value"], flagParams: ["display"], usage: "thawctl set <key>=<value> [--display <uuid>]", needsAuth: true),
        Command(name: "toggle-setting", host: "toggle", valueParams: ["key"], flagParams: ["display"], usage: "thawctl toggle-setting <key> [--display <uuid>]", needsAuth: true),
        Command(name: "authorize", host: "authorize", valueParams: [], flagParams: [], usage: "thawctl authorize", needsAuth: false),
        Command(name: "reveal-item", host: "reveal-item", valueParams: [], flagParams: ["bundle", "item-id"], usage: "thawctl reveal-item (--bundle <id> | --item-id <id>)", needsAuth: true),
    ]
}

// MARK: - Argument parsing

enum ParseError: Error, CustomStringConvertible, Equatable {
    case unknownCommand(String)
    case missingValue(command: String, param: String)
    case unexpectedArgument(String)
    case invalidPair(String)
    case noReplyChannel

    var description: String {
        switch self {
        case let .unknownCommand(c): "unknown command: \(c)"
        case let .missingValue(command, param): "\(command): missing value for \(param)"
        case let .unexpectedArgument(a): "unexpected argument: \(a)"
        case let .invalidPair(a): "expected key=value, got: \(a)"
        case .noReplyChannel:
            "get: thawctl can't receive the reply. Thaw sends setting values only to a callback URL that the approved app handles itself, so read settings from the ThawCtl app or your own app's callback."
        }
    }
}

/// Returns (host, queryItems) or nil when args request help / are empty.
func parse(_ args: [String]) throws -> (host: String, query: [URLQueryItem])? {
    guard let first = args.first, !first.hasPrefix("-") else { return nil }
    // The reply would go nowhere, so refuse before sending anything.
    guard first != "get" else { throw ParseError.noReplyChannel }
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
            try readPair(arg, for: command, into: &values)
        } else if command.valueParams.count == 1, values[command.valueParams[0]] == nil {
            // Positional shorthand: thawctl toggle-setting someKey is toggle-setting key=someKey.
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

/// Reads a name=value argument into the command's values.
private func readPair(_ arg: String, for command: Command, into values: inout [String: String]) throws {
    let pair = arg.split(separator: "=", maxSplits: 1).map(String.init)
    guard pair.count == 2 else {
        throw ParseError.invalidPair(arg)
    }
    if command.valueParams.contains(pair[0]) {
        values[pair[0]] = pair[1]
    } else if command.valueParams == ["key", "value"], values["key"] == nil, values["value"] == nil {
        // The documented form: thawctl set showOnHover=true is set key=showOnHover value=true.
        values["key"] = pair[0]
        values["value"] = pair[1]
    } else {
        throw ParseError.invalidPair(arg)
    }
}
