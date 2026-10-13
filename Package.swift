// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iTabs",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "iTabs",
            path: "Sources/iTabs"
        )
    ]
)
