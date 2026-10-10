// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ThawCtl",
    platforms: [.macOS(.v14)],
    targets: [
        // GUI debug playground for the thaw:// control plane.
        .executableTarget(name: "ThawCtl"),
        // Headline CLI client of the same plane.
        // Target name must differ from "ThawCtl" beyond case: APFS is
        // case-insensitive, so Sources/ AND .build/debug/<name> would
        // otherwise collide and running the CLI launches the GUI instead.
        .executableTarget(name: "thawctl-cli", path: "Sources/ThawCtlCLI"),
    ]
)
