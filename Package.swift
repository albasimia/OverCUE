// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OverCUE",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "OverCUECore", targets: ["OverCUECore"]),
        .executable(name: "overcue", targets: ["OverCUEBridge"]),
        .executable(name: "overcue-checks", targets: ["OverCUEChecks"]),
        .executable(name: "overcue-probe", targets: ["OverCUEProbe"]),
    ],
    targets: [
        .target(name: "OverCUECore"),
        .executableTarget(
            name: "OverCUEBridge",
            dependencies: ["OverCUECore"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreMIDI"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "OverCUEProbe",
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "OverCUEChecks",
            dependencies: ["OverCUECore"]
        ),
    ]
)
