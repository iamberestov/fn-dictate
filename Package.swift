// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FnDictate",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "FnDictate",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
