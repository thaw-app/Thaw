// swift-tools-version: 6.4

import PackageDescription

/// Helper observations travel over stdout via the client and shared Core framing; XPC can replace the pipe behind the client.
/// No external dependencies avoids helper rpath requirements; identity assembly stays in the app's in-process path.
let package = Package(
    name: "ThawAX",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        // Static: the helper has no rpath, so a dynamic build aborts it in dyld.
        .library(name: "ThawAXCore", type: .static, targets: ["ThawAXCore"]),
        .library(name: "ThawAXClient", targets: ["ThawAXClient"]),
        .executable(name: "ThawAXHelper", targets: ["ThawAXHelper"]),
    ],
    targets: [
        .target(
            name: "ThawAXCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ThawAXClient",
            dependencies: ["ThawAXCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ThawAXHelper",
            dependencies: ["ThawAXCore"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            // Xcode 27.0 wraps static ThawAXCore in a framework, so the Contents/Helpers executable needs this rpath.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "ThawAXCoreTests",
            dependencies: ["ThawAXCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
