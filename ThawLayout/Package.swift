// swift-tools-version: 6.4

import PackageDescription

/// Pure layout planning from a desired arrangement and live snapshot.
/// Accessibility, position-table writes, and drags stay with the app and PlatformRuntimeKit.
let package = Package(
    name: "ThawLayout",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .library(name: "ThawLayout", targets: ["ThawLayout"]),
    ],
    dependencies: [
        .package(path: "../MenuBarModel"),
    ],
    targets: [
        .target(
            name: "ThawLayout",
            dependencies: [
                .product(name: "MenuBarModel", package: "MenuBarModel"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ThawLayoutTests",
            dependencies: [
                "ThawLayout",
                .product(name: "MenuBarModel", package: "MenuBarModel"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
