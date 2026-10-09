// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "freewind-traffic-monitor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "freewind-traffic-monitor",
            targets: ["freewind_traffic_monitor"]
        ),
    ],
    targets: [
        .target(
            name: "TrafficMonitorCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "freewind_traffic_monitor",
            dependencies: ["TrafficMonitorCore"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "TrafficMonitorCoreTests",
            dependencies: ["TrafficMonitorCore"],
            path: "Tests"
        ),
    ]
)
