// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacCompose",
    platforms: [.macOS("27.2")],
    targets: [
        .target(name: "MacComposeCore", resources: [.copy("Resources")]),
        .executableTarget(name: "MacCompose", dependencies: ["MacComposeCore"]),
        .executableTarget(name: "MacComposeChecks", dependencies: ["MacComposeCore"])
    ]
)
