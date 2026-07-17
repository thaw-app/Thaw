// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MenuBarModel",
    platforms: [.macOS(.v26)],
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
