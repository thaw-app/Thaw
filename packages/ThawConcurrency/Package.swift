// swift-tools-version: 6.4

import PackageDescription

/// Shared concurrency primitives for the app and its packages.
///
/// The one-shot continuation and abandoning timeout are written once here;
/// per-call-site copies lost cancellations to registration-order differences.
let package = Package(
    name: "ThawConcurrency",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .library(name: "ThawConcurrency", targets: ["ThawConcurrency"]),
    ],
    targets: [
        .target(
            name: "ThawConcurrency",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ThawConcurrencyTests",
            dependencies: ["ThawConcurrency"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
