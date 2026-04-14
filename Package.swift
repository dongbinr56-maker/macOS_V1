// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AIWebUsageMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AIWebUsageMonitor",
            targets: ["AIWebUsageMonitor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AIWebUsageMonitor",
            path: "Sources/AIWebUsageMonitor",
            resources: [
                .copy("Resources/PixelOfficeAssets")
            ]
        ),
        .testTarget(
            name: "AIWebUsageMonitorTests",
            dependencies: ["AIWebUsageMonitor"],
            path: "Tests/AIWebUsageMonitorTests"
        )
    ]
)
