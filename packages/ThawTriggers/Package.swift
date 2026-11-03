// swift-tools-version: 6.4

import PackageDescription

/// The Triggers module: shows chosen menu bar items while an app runs, through thaw:// links.
/// TriggersCore holds what can be tested without a window.
let package = Package(
    name: "ThawTriggers",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .executable(name: "ThawTriggers", targets: ["ThawTriggers"]),
    ],
    dependencies: [
        .package(path: "../ThawModuleKit"),
    ],
    targets: [
        .target(
            name: "TriggersCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ThawTriggers",
            dependencies: [
                "TriggersCore",
                .product(name: "ThawModuleKit", package: "ThawModuleKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TriggersCoreTests",
            dependencies: ["TriggersCore", .product(name: "ThawModuleTestSupport", package: "ThawModuleKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
