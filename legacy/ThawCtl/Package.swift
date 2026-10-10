// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ThawCtl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ThawCtl"),
    ]
)
