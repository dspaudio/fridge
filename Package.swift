// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Fridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FridgeApp", targets: ["FridgeApp"]),
        .executable(name: "fridge", targets: ["FridgeCLI"])
    ],
    targets: [
        .target(name: "FridgeModels", path: "Models"),
        .target(
            name: "FridgeProcessWatcher",
            dependencies: ["FridgeModels"],
            path: "ProcessWatcher"
        ),
        .target(
            name: "FridgeFreezeController",
            dependencies: ["FridgeModels", "FridgeProcessWatcher"],
            path: "FreezeController"
        ),
        .target(
            name: "FridgeCore",
            dependencies: ["FridgeModels", "FridgeProcessWatcher", "FridgeFreezeController"],
            path: "Core"
        ),
        .target(
            name: "FridgeUI",
            dependencies: ["FridgeCore", "FridgeModels"],
            path: "UI"
        ),
        .executableTarget(
            name: "FridgeApp",
            dependencies: ["FridgeCore", "FridgeUI"],
            path: "App"
        ),
        .executableTarget(
            name: "FridgeCLI",
            dependencies: ["FridgeCore", "FridgeModels"],
            path: "CLI"
        )
    ]
)
