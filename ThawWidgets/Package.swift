// swift-tools-version: 6.4

import PackageDescription

/// The Widgets module: one menu bar icon that combines battery, Wi-Fi and other readings.
/// WidgetsCore holds everything testable; ThawWidgets only starts it.
let package = Package(
    name: "ThawWidgets",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .executable(name: "ThawWidgets", targets: ["ThawWidgets"]),
    ],
    dependencies: [
        .package(path: "../MenuBarModel"),
        .package(path: "../ThawModuleKit"),
        .package(url: "https://github.com/thaw-app/ThawUI", exact: "1.1.0"),
    ],
    targets: [
        .target(
            name: "WidgetsCore",
            dependencies: [
                .product(name: "MenuBarModel", package: "MenuBarModel"),
                .product(name: "ThawModuleKit", package: "ThawModuleKit"),
                .product(name: "ThawUI", package: "ThawUI"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ThawWidgets",
            dependencies: ["WidgetsCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WidgetsCoreTests",
            dependencies: ["WidgetsCore", .product(name: "ThawModuleTestSupport", package: "ThawModuleKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
