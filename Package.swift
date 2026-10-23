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
        // Vendored from github.com/Jakubantalik/Libraries.dev (MIT); see Vendor/ThinkingOrbsKit/PROVENANCE.md.
        .target(
            name: "ThinkingOrbsKit",
            path: "Vendor/ThinkingOrbsKit",
            exclude: ["LICENSE", "PROVENANCE.md"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FnDictate",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                "ThinkingOrbsKit",
            ],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
