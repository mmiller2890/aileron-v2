// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AileronV2",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .library(
            name: "AileronCore",
            targets: ["AileronCore"]
        ),
        .executable(
            name: "Aileron",
            targets: ["AileronApp"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "e0c6103bc87a88d25276cad491c86e757f58c865"
        )
    ],
    targets: [
        .target(
            name: "CSileroVad",
            path: "Sources/CSileroVad",
            exclude: ["LICENSE"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include/dsp"),
                .define("SILERO_VAD_ENABLE_NEON", to: "1")
            ]
        ),
        .target(
            name: "AileronCore",
            dependencies: [
                "CSileroVad",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/AileronCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Security"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "AileronApp",
            dependencies: [
                "AileronCore"
            ],
            path: "Sources/AileronApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "AileronCoreTests",
            dependencies: [
                "AileronCore"
            ],
            path: "Tests/AileronCoreTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
