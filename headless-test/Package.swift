// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Headless",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Headless", targets: ["Headless"])
    ],
    targets: [
        .executableTarget(
            name: "Headless",
            path: "Sources/Headless"
        )
    ]
)
