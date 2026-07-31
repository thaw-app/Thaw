// swift-tools-version: 6.0

import PackageDescription

// Fuzzing harnesses for Thaw's attacker-reachable parsers.
//
// This is a separate package rather than part of Thaw.xcodeproj because
// libFuzzer needs an executable built with `-sanitize=fuzzer`, which supplies
// its own `main`. Sources under test are symlinked in rather than copied, so
// the harness always compiles the same file the app ships.
//
// Build and run the Linux libFuzzer harness (avoid `swift build` here —
// SwiftPM's `--defsym main=<Module>_main` fights libFuzzer's entry point):
//   mkdir -p Fuzzing/.build/release
//   swiftc -parse-as-library -O -sanitize=fuzzer,address \
//     -o Fuzzing/.build/release/FuzzSettingsURI \
//     Fuzzing/Sources/FuzzSettingsURI/*.swift
//   ./Fuzzing/.build/release/FuzzSettingsURI -max_total_time=60 Fuzzing/Corpus/SettingsURI
//
// Replay the corpus on macOS (no libFuzzer):
//   swift build --package-path Fuzzing -c release -Xswiftc -DFUZZ_REPLAY
//   ./Fuzzing/.build/release/FuzzSettingsURI Fuzzing/Corpus/SettingsURI
let package = Package(
    name: "ThawFuzz",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FuzzSettingsURI",
            path: "Sources/FuzzSettingsURI"
        ),
    ]
)
