// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OverCUE",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "OverCUECore", targets: ["OverCUECore"]),
        .executable(name: "overcue-cli", targets: ["OverCUEBridge"]),
        .executable(name: "OverCUE", targets: ["OverCUEApp"]),
        .executable(name: "overcue-checks", targets: ["OverCUEChecks"]),
        .executable(name: "overcue-probe", targets: ["OverCUEProbe"]),
    ],
    targets: [
        .target(
            name: "OverCUECore",
            resources: [
                .process("Resources"),
            ]
        ),
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
        .executableTarget(
            name: "OverCUEApp",
            dependencies: ["OverCUECore"],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
