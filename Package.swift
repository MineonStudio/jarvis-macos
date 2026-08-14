// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Jarvis",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Jarvis", targets: ["Jarvis"])
    ],
    targets: [
        .executableTarget(
            name: "Jarvis",
            path: "Sources/Jarvis",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "JarvisTests",
            dependencies: ["Jarvis"],
            path: "Tests/JarvisTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
