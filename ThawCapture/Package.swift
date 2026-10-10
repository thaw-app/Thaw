// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ThawCapture",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "ThawCapture", targets: ["ThawCapture"]),
    ],
    dependencies: [
        .package(path: "../MenuBarModel"),
        .package(path: "../ThawConcurrency"),
    ],
    targets: [
        .target(
            name: "ThawCapture",
            dependencies: [
                .product(name: "MenuBarModel", package: "MenuBarModel"),
                .product(name: "ThawConcurrency", package: "ThawConcurrency"),
            ]
        ),
        .testTarget(
            name: "ThawCaptureTests",
            dependencies: ["ThawCapture"]
        ),
    ]
)
