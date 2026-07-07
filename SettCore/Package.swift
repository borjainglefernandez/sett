// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SettCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "SettCore", targets: ["SettCore"])
    ],
    targets: [
        .target(
            name: "SettCore",
            resources: [
                .process("Seed/ExerciseSeed.json"),
                .process("Progression/progression_config.json")
            ]
        ),
        .testTarget(name: "SettCoreTests", dependencies: ["SettCore"])
    ]
)
