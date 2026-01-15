// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FootstepNoiseAnalyzer",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FootstepNoiseAnalyzer",
            targets: ["FootstepNoiseAnalyzer"]
        ),
    ],
    dependencies: [
        // SwiftCheck for property-based testing
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "FootstepNoiseAnalyzer",
            dependencies: [],
            path: "FootstepNoiseAnalyzer"
        ),
        .testTarget(
            name: "FootstepNoiseAnalyzerTests",
            dependencies: [
                "FootstepNoiseAnalyzer",
                "SwiftCheck",
            ],
            path: "FootstepNoiseAnalyzerTests"
        ),
    ]
)
