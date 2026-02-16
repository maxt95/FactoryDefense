// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FactoryDefense",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "GameContent", targets: ["GameContent"]),
        .library(name: "GameSimulation", targets: ["GameSimulation"]),
        .library(name: "GameRendering", targets: ["GameRendering"]),
        .library(name: "GameUI", targets: ["GameUI"]),
        .library(name: "GamePlatform", targets: ["GamePlatform"]),
        .executable(name: "FactoryDefense", targets: ["FactoryDefense"]),
        .executable(name: "FactoryDefensePrototype", targets: ["FactoryDefensePrototype"])
    ],
    targets: [
        .target(
            name: "GameContent"
        ),
        .target(
            name: "GameSimulation",
            dependencies: ["GameContent"]
        ),
        .target(
            name: "GameRendering",
            dependencies: ["GameSimulation"],
            resources: [.process("Shaders")]
        ),
        .target(
            name: "GameUI",
            dependencies: ["GameSimulation", "GameContent"]
        ),
        .target(
            name: "GamePlatform",
            dependencies: ["GameSimulation"]
        ),
        .executableTarget(
            name: "FactoryDefense",
            dependencies: ["GameSimulation", "GameRendering", "GameUI", "GamePlatform"]
        ),
        .executableTarget(
            name: "FactoryDefensePrototype",
            dependencies: ["GameSimulation", "GameContent", "GamePlatform"]
        ),
        .testTarget(
            name: "GameContentTests",
            dependencies: ["GameContent"]
        ),
        .testTarget(
            name: "GameSimulationTests",
            dependencies: ["GameSimulation", "GameContent"]
        ),
        .testTarget(
            name: "GameRenderingTests",
            dependencies: ["GameRendering", "GameSimulation"]
        ),
        .testTarget(
            name: "GamePlatformTests",
            dependencies: ["GamePlatform", "GameSimulation"]
        ),
        .testTarget(
            name: "GameUITests",
            dependencies: ["GameUI"]
        )
    ]
)
