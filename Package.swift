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
        .executableTarget(
            name: "freewind_traffic_monitor",
            path: "Sources"
        ),
    ]
)
