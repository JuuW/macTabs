// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macTabs",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "macTabs",
            path: "Sources/macTabs"
        )
    ]
)
