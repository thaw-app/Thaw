// swift-tools-version: 6.0

import PackageDescription

// Fuzzing harnesses for Thaw's attacker-reachable parsers, kept out of the app project because
// libFuzzer supplies its own main. Sources are symlinked, so the harness compiles the shipped file.
//
// On Linux, build with swiftc; swift build's main symbol fights libFuzzer's entry point:
//   mkdir -p Fuzzing/.build/release
//   swiftc -parse-as-library -O -sanitize=fuzzer,address \
//     -o Fuzzing/.build/release/FuzzSettingsURI \
//     Fuzzing/Sources/FuzzSettingsURI/*.swift
//   ./Fuzzing/.build/release/FuzzSettingsURI -max_total_time=60 Fuzzing/Corpus/SettingsURI
//
// On macOS, replay the corpus without libFuzzer:
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
