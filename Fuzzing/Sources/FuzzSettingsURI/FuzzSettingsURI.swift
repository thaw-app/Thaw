//
//  FuzzSettingsURI.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  libFuzzer harness for SettingsURIParser, which reads thaw:// URLs any app can send.
//  A failed property counts as a finding, like a crash.
//
//  -sanitize=fuzzer works only on Linux, so fuzzing runs in CI; -DFUZZ_REPLAY replays the corpus on macOS.
//

import Foundation

/// Called by libFuzzer for each generated input. It always returns 0; failures trap.
@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ start: UnsafeRawPointer, _ count: Int) -> CInt {
    let bytes = UnsafeRawBufferPointer(start: start, count: count)

    guard let text = String(bytes: bytes, encoding: .utf8), let url = URL(string: text) else {
        return 0
    }

    // Parsing is total: whatever arrives over the wire yields a request instead of trapping.
    let request = SettingsURIParser.parse(url)

    // Parsing is deterministic and keeps no hidden state.
    precondition(request == SettingsURIParser.parse(url), "SettingsURIParser is not deterministic for \(text)")

    checkAuthorization(request, text: text)
    checkHost(request.route, host: url.host?.lowercased() ?? "", text: text)
    checkParameters(request.route, text: text)
    return 0
}

/// Every route that changes settings, acts on items or exports data is gated, and only the version read skips the sender check.
private func checkAuthorization(_ request: SettingsURIRequest, text: String) {
    switch request.route {
    case .set, .toggle, .get, .authorize, .revealItem, .launcher, .proxyPress, .toggleThawBar, .dumpItems, .malformed:
        precondition(request.requiresAuthorization, "Gated route must require authorization: \(text)")
    case .action, .unrecognized:
        precondition(!request.requiresAuthorization, "Ungated route must not require authorization: \(text)")
    }

    if request.isVersionRead {
        guard case let .get(query) = request.route else {
            preconditionFailure("isVersionRead on a route other than get: \(text)")
        }
        precondition(query.key == "version", "Version bypass widened for \(text)")
    }
}

/// Each route comes from exactly the host that names it, so two hosts can never alias one action.
private func checkHost(_ route: SettingsURIRoute, host: String, text: String) {
    switch route {
    case let .action(action):
        precondition(action.rawValue == host, "Action \(action.rawValue) did not round-trip for \(text)")
    case let .launcher(operation, _):
        precondition(operation.rawValue == host, "Launcher operation \(operation.rawValue) did not round-trip for \(text)")
    case let .malformed(malformedHost):
        precondition(malformedHost == host, "Malformed host differs from the URL's for \(text)")
        precondition(
            ["set", "toggle", "get", "reveal-item", "proxy-press"].contains(host),
            "Only hosts with required parameters can be malformed: \(text)"
        )
    case let .unrecognized(unrecognizedHost):
        precondition(unrecognizedHost == host, "Unrecognized host differs from the URL's for \(text)")
        precondition(
            SettingsURIAction(rawValue: host) == nil && LauncherURIOperation(rawValue: host) == nil,
            "A known host was reported as unrecognized: \(text)"
        )
    case .set, .toggle, .get, .authorize, .revealItem, .proxyPress, .toggleThawBar, .dumpItems:
        precondition(builtInHost(of: route) == host, "Route came from the wrong host for \(text)")
    }
}

/// The one host each fixed route is spelled with, written out here so a parser change can't move both sides.
private func builtInHost(of route: SettingsURIRoute) -> String? {
    switch route {
    case .set: "set"
    case .toggle: "toggle"
    case .get: "get"
    case .authorize: "authorize"
    case .revealItem: "reveal-item"
    case .proxyPress: "proxy-press"
    case .toggleThawBar: "toggle-thawbar"
    case .dumpItems: "dump-items"
    case .action, .launcher, .malformed, .unrecognized: nil
    }
}

/// Parameters the parser promises are present and non-empty really are.
private func checkParameters(_ route: SettingsURIRoute, text: String) {
    switch route {
    case let .proxyPress(bundle):
        precondition(!bundle.isEmpty, "proxy-press carried an empty bundle: \(text)")
    case let .launcher(operation, query):
        let optionals = [query.identifier, query.callback, query.requestId]
        precondition(!optionals.contains(""), "A launcher parameter was an empty string: \(text)")
        precondition(
            operation.identifierParameter != nil || query.identifier == nil,
            "\(operation.rawValue) carried an identifier it does not take: \(text)"
        )
        precondition((operation == .moveItem) == (query.move != nil), "Move parameters on the wrong operation: \(text)")
        if let move = query.move {
            precondition(!move.itemIDs.contains("") && move.afterID != "", "A move parameter was an empty string: \(text)")
        }
    default:
        break
    }
}

#if FUZZ_REPLAY
    /// Replays every file in a corpus directory through the harness, for macOS where libFuzzer is unavailable.
    @main
    enum Replay {
        static func main() {
            let arguments = CommandLine.arguments
            guard arguments.count > 1 else {
                FileHandle.standardError.write(Data("usage: FuzzSettingsURI <corpus-dir>...\n".utf8))
                exit(2)
            }

            var replayed = 0
            for directory in arguments.dropFirst() {
                let url = URL(fileURLWithPath: directory)
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil
                )) ?? []

                for file in files {
                    guard let data = try? Data(contentsOf: file) else { continue }
                    data.withUnsafeBytes { raw in
                        guard let base = raw.baseAddress else { return }
                        _ = LLVMFuzzerTestOneInput(base, raw.count)
                    }
                    replayed += 1
                }
            }

            print("replayed \(replayed) corpus inputs; all properties held")
        }
    }
#endif
