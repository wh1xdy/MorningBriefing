// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MorningBriefingApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MorningBriefingApp",
            path: "Sources/MorningBriefingApp"
        )
    ]
)
