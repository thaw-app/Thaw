//
//  FuzzSettingsURI.swift
//  Project: Thaw
//
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//
//  libFuzzer harness for `SettingsURIParser`, the one parser in Thaw that
//  consumes attacker-reachable input: any app on the system can hand it a
//  `thaw://` URL via an Apple Event.
//
//  The harness asserts properties, not just absence of crashes. A property
//  failure is as much a finding as a segfault.
//
//  Swift's `-sanitize=fuzzer` is Linux-only — it is rejected on both
//  arm64 and x86_64 Apple targets — so real fuzzing runs in CI on Linux.
//  Building with `-DFUZZ_REPLAY` instead produces a plain executable that
//  replays a corpus directory, which keeps the harness and its properties
//  runnable on macOS during development.
//

import Foundation

/// Entry point invoked by libFuzzer for each generated input.
///
/// Returning a non-zero value is reserved by libFuzzer, so this always
/// returns 0; failures surface as trapped preconditions.
@_cdecl("LLVMFuzzerTestOneInput")
public func LLVMFuzzerTestOneInput(_ start: UnsafeRawPointer, _ count: Int) -> CInt {
    let bytes = UnsafeRawBufferPointer(start: start, count: count)

    guard let text = String(bytes: bytes, encoding: .utf8) else {
        return 0
    }
    guard let url = URL(string: text) else {
        return 0
    }

    // Property 1: parsing is total. Any URL must yield a request rather than
    // trapping, because AppDelegate hands it whatever arrives over the wire.
    let request = SettingsURIParser.parse(url)

    // Property 2: parsing is deterministic and free of hidden state. Two parses
    // of the same URL must agree; a mismatch means the parser depends on
    // something other than its input.
    let second = SettingsURIParser.parse(url)
    precondition(
        request == second,
        "SettingsURIParser is not deterministic for \(text)"
    )

    // Property 3: the authorization gate is a function of the route alone, and
    // only settings routes pass through it. If a parameterless action ever
    // reported requiresAuthorization, it would raise an approval dialog that
    // no integration expects.
    switch request.route {
    case .set, .toggle, .get, .authorize, .malformed:
        precondition(
            request.requiresAuthorization,
            "Settings route must require authorization: \(text)"
        )
    case .action, .unrecognized:
        precondition(
            !request.requiresAuthorization,
            "Non-settings route must not require authorization: \(text)"
        )
    }

    // Property 4: the version bypass is exactly `get?key=version`. This is the
    // only route that skips authorization, so any widening of it is a
    // privilege boundary change.
    if request.isVersionQuery {
        guard case let .get(key, _, _, _, _) = request.route else {
            preconditionFailure("isVersionQuery on a non-get route: \(text)")
        }
        precondition(key == "version", "Version bypass widened for \(text)")
    }

    // Property 5: a decoded action must round-trip to the host that produced
    // it, so host matching cannot silently alias two different actions.
    if case let .action(action) = request.route {
        precondition(
            url.host?.lowercased() == action.rawValue,
            "Action \(action.rawValue) did not round-trip for \(text)"
        )
    }

    return 0
}

#if FUZZ_REPLAY
    /// Replays every file in a corpus directory through the harness.
    ///
    /// Used on macOS, where libFuzzer is unavailable, to prove the harness
    /// compiles and its properties hold over the committed corpus.
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
