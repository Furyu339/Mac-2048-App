// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UIApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "UIApp", targets: ["UIApp"])
    ],
    targets: [
        .executableTarget(
            name: "UIApp",
            path: "Sources/UIApp"
        )
    ]
)
