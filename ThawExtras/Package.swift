// swift-tools-version: 6.4

import PackageDescription

/// Stand-ins for Apple menu extras Thaw removes natively.
///
/// On macOS 27 concealment is keyed by the bundle identifier of the process
/// that owns a status item, so each stand-in has to come from its own bundle to
/// be hidden or ordered on its own. ThawExtraHelper is one executable wrapped
/// into one .app per extra at build time; its bundle identifier picks the
/// role. Like ThawAX, the package has no dependencies, so the bundles need no
/// framework @rpath inside the app.
let package = Package(
    name: "ThawExtras",
    platforms: [
        .macOS(.v27),
    ],
    products: [
        .executable(name: "ThawExtraHelper", targets: ["ThawExtraHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "ThawExtraHelper",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
