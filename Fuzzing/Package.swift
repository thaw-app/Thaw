// swift-tools-version: 6.0

import PackageDescription

// Fuzzing harnesses for Thaw's attacker-reachable parsers.
//
// This is a separate package rather than part of Thaw.xcodeproj because
// libFuzzer needs an executable built with `-sanitize=fuzzer`, which supplies
// its own `main`. Sources under test are symlinked in rather than copied, so
// the harness always compiles the same file the app ships.
//
// Build and run:
//   swift build --package-path Fuzzing -c release \
//     -Xswiftc -sanitize=fuzzer,address -Xswiftc -parse-as-library
//   ./Fuzzing/.build/release/FuzzSettingsURI -max_total_time=60 Fuzzing/Corpus/SettingsURI
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
