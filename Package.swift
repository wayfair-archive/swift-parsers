// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Parsers",
    products: [
        .library(
            name: "Parsers",
            targets: ["Parsers"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/wayfair/Prelude", .branch("master")
        )
    ],
    targets: [
        .target(
            name: "Parsers",
            dependencies: ["Prelude"]
        ),
        .testTarget(
            name: "ParsersTests",
            dependencies: ["Parsers"]
        ),
    ]
)
