// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Footprint",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Footprint",
            targets: ["Footprint"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Footprint",
            path: "Sources/Footprint",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "FootprintTests",
            dependencies: ["Footprint"],
            path: "Tests/FootprintTests"
        ),
    ]
)
