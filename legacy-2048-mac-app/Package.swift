// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TwoZeroFourEight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TwoZeroFourEight", targets: ["App"])
    ],
    targets: [
        .executableTarget(
            name: "App",
            path: "Sources/App",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
