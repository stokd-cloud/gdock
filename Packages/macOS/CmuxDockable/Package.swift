// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CmuxDockable",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "CmuxDockable",
            targets: ["CmuxDockable"]
        ),
    ],
    targets: [
        .target(
            name: "CmuxDockable",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxDockableTests",
            dependencies: [
                "CmuxDockable",
            ]
        ),
    ]
)
