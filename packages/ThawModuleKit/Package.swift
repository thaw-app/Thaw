// swift-tools-version: 6.4

import PackageDescription

/// What Thaw and its modules share: the hook script model and the events
/// Thaw posts for modules. It has no dependencies, so a module can link it
/// without pulling in the rest of Thaw.
let package = Package(
    name: "ThawModuleKit",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .library(name: "ThawModuleKit", targets: ["ThawModuleKit"]),
        // For the modules' tests only.
        .library(name: "ThawModuleTestSupport", targets: ["ThawModuleTestSupport"]),
    ],
    targets: [
        .target(
            name: "ThawModuleKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "ThawModuleTestSupport",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ThawModuleKitTests",
            dependencies: ["ThawModuleKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
