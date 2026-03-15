import CaptureKit
import Foundation

guard CommandLine.arguments.count >= 5,
      CommandLine.arguments[1] == "--capture",
      let outIndex = CommandLine.arguments.firstIndex(of: "--out"),
      CommandLine.arguments.indices.contains(outIndex + 1) else {
    fputs("Usage: swift run flexlite-audio-export --capture <bundle-path> --out <wav-path> [--stream <stream-id|rx>] [--assumption auto|pcm16Mono24k|pcmFloat32Mono24k|pcmFloat32Stereo24k]\n", stderr)
    exit(1)
}

let captureURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[outIndex + 1])
let streamIndex = CommandLine.arguments.firstIndex(of: "--stream")
let streamValue = streamIndex.flatMap { index in
    CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil
}
let streamID = (streamValue == nil || streamValue == "rx") ? nil : streamValue
let assumptionIndex = CommandLine.arguments.firstIndex(of: "--assumption")
let assumptionValue = assumptionIndex.flatMap { index in
    CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil
}
let assumption = assumptionValue.flatMap(AudioExportAssumption.init(rawValue:)) ?? .auto

try AudioExportService().exportWAV(bundleAt: captureURL, streamID: streamID, assumption: assumption, outputURL: outputURL)
print("Wrote \(outputURL.path)")
