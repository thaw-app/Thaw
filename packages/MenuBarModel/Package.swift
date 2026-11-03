// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MenuBarModel",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "MenuBarModel", type: .dynamic, targets: ["MenuBarModel"]),
    ],
    targets: [
        .target(name: "MenuBarModel"),
        .testTarget(
            name: "MenuBarModelTests",
            dependencies: ["MenuBarModel"]
        ),
    ]
)
