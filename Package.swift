// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Jarvis",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Jarvis", targets: ["Jarvis"])
    ],
    targets: [
        .executableTarget(
            name: "Jarvis",
            path: "Sources/Jarvis"
        ),
        .testTarget(
            name: "JarvisTests",
            dependencies: ["Jarvis"],
            path: "Tests/JarvisTests"
        )
    ]
)
