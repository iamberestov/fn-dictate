// swift-tools-version:6.0
// Throwaway benchmark: runs Apple speech, Parakeet (FluidAudio) and Whisper (WhisperKit) on the same clips.
import PackageDescription

let package = Package(
    name: "stt-bench",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "stt-bench",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Speech framework needs usage descriptions even in a command-line tool.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"]),
            ]
        ),
    ]
)
