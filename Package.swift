// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchClaudeApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NotchClaudeApp", targets: ["NotchClaudeApp"])
    ],
    targets: [
        .executableTarget(
            name: "NotchClaudeApp",
            path: "Sources/NotchClaudeApp"
        )
    ]
)
