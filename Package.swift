// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlexLite",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FlexLiteApp", targets: ["FlexLiteApp"]),
        .executable(name: "flexlite-inspect", targets: ["FlexLiteInspectCLI"]),
        .executable(name: "flexlite-replay", targets: ["FlexLiteReplayCLI"]),
        .executable(name: "flexlite-audio-export", targets: ["FlexLiteAudioExportCLI"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Transport", targets: ["Transport"]),
        .library(name: "SmartSDRProtocol", targets: ["SmartSDRProtocol"]),
        .library(name: "Vita49", targets: ["Vita49"]),
        .library(name: "Audio", targets: ["Audio"]),
        .library(name: "CW", targets: ["CW"]),
        .library(name: "MIDI", targets: ["MIDI"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"])
    ],
    targets: [
        .executableTarget(
            name: "FlexLiteApp",
            dependencies: ["Core", "SmartSDRProtocol", "Audio", "CW", "MIDI", "Diagnostics", "CaptureKit"],
            path: "Sources/FlexLiteApp"
        ),
        .executableTarget(
            name: "FlexLiteInspectCLI",
            dependencies: ["CaptureKit"],
            path: "Sources/FlexLiteInspectCLI"
        ),
        .executableTarget(
            name: "FlexLiteReplayCLI",
            dependencies: ["CaptureKit", "SmartSDRProtocol"],
            path: "Sources/FlexLiteReplayCLI"
        ),
        .executableTarget(
            name: "FlexLiteAudioExportCLI",
            dependencies: ["CaptureKit"],
            path: "Sources/FlexLiteAudioExportCLI"
        ),
        .target(
            name: "Core",
            dependencies: ["Transport", "SmartSDRProtocol", "Vita49", "Audio", "CW", "MIDI", "Diagnostics", "CaptureKit"],
            path: "Sources/Core"
        ),
        .target(
            name: "CaptureKit",
            dependencies: ["SmartSDRProtocol", "Vita49", "Audio"],
            path: "Sources/CaptureKit"
        ),
        .target(
            name: "Transport",
            dependencies: ["Diagnostics"],
            path: "Sources/Transport"
        ),
        .target(
            name: "SmartSDRProtocol",
            dependencies: ["Diagnostics"],
            path: "Sources/SmartSDRProtocol"
        ),
        .target(
            name: "Vita49",
            path: "Sources/Vita49"
        ),
        .target(
            name: "Audio",
            dependencies: ["Vita49", "Diagnostics"],
            path: "Sources/Audio"
        ),
        .target(
            name: "CW",
            dependencies: ["Diagnostics"],
            path: "Sources/CW"
        ),
        .target(
            name: "MIDI",
            dependencies: ["Diagnostics"],
            path: "Sources/MIDI"
        ),
        .target(
            name: "Diagnostics",
            path: "Sources/Diagnostics"
        ),
        .testTarget(
            name: "SmartSDRProtocolTests",
            dependencies: ["SmartSDRProtocol"],
            path: "Tests/SmartSDRProtocolTests"
        ),
        .testTarget(
            name: "Vita49Tests",
            dependencies: ["Vita49"],
            path: "Tests/Vita49Tests"
        ),
        .testTarget(
            name: "AudioPipelineTests",
            dependencies: ["Audio", "Vita49"],
            path: "Tests/AudioPipelineTests"
        ),
        .testTarget(
            name: "CWEngineTests",
            dependencies: ["CW"],
            path: "Tests/CWEngineTests"
        ),
        .testTarget(
            name: "MidiMappingTests",
            dependencies: ["MIDI"],
            path: "Tests/MidiMappingTests"
        ),
        .testTarget(
            name: "SessionTests",
            dependencies: ["Core", "Transport", "SmartSDRProtocol", "CaptureKit"],
            path: "Tests/SessionTests"
        ),
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit", "SmartSDRProtocol", "Vita49"],
            path: "Tests/CaptureKitTests"
        )
    ]
)
