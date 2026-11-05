// swift-tools-version: 6.4

import PackageDescription

/// The Scripts module (identifier automation): runs the user's scripts when Thaw switches profiles.
/// AutomationCore holds what can be tested without a window.
let package = Package(
    name: "ThawAutomation",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .executable(name: "ThawAutomation", targets: ["ThawAutomation"]),
    ],
    dependencies: [
        .package(path: "../ThawModuleKit"),
        .package(path: "../ThawConcurrency"),
        .package(url: "https://github.com/swiftlang/swift-subprocess", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AutomationCore",
            dependencies: [
                .product(name: "ThawModuleKit", package: "ThawModuleKit"),
                .product(name: "ThawConcurrency", package: "ThawConcurrency"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ThawAutomation",
            dependencies: [
                "AutomationCore",
                .product(name: "ThawModuleKit", package: "ThawModuleKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AutomationCoreTests",
            dependencies: [
                "AutomationCore",
                .product(name: "ThawModuleKit", package: "ThawModuleKit"),
                .product(name: "ThawModuleTestSupport", package: "ThawModuleKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
