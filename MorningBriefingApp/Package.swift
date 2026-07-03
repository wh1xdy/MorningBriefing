// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MorningBriefingApp",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MorningBriefingApp",
            path: "Sources/MorningBriefingApp"
        ),
        .testTarget(
            name: "MorningBriefingAppTests",
            dependencies: ["MorningBriefingApp"],
            path: "Tests/MorningBriefingAppTests"
        )
    ]
)
