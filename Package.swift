// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WindowSwitcherForMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "PlatformServices", targets: ["PlatformServices"]),
        .executable(name: "WindowSwitcherForMacApp", targets: ["WindowSwitcherForMacApp"]),
        .executable(name: "ValidationRunner", targets: ["ValidationRunner"]),
    ],
    targets: [
        .target(name: "AppCore"),
        .target(
            name: "PlatformServices",
            dependencies: ["AppCore"]
        ),
        .executableTarget(
            name: "WindowSwitcherForMacApp",
            dependencies: ["AppCore", "PlatformServices"]
        ),
        .executableTarget(
            name: "ValidationRunner",
            dependencies: ["AppCore"]
        ),
    ]
)
