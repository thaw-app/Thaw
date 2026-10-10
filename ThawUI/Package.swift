// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ThawUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ThawUI", targets: ["ThawUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/buh/CompactSlider", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "ThawUI",
            dependencies: ["CompactSlider"]
        ),
        .testTarget(
            name: "ThawUITests",
            dependencies: ["ThawUI"]
        ),
    ]
)
