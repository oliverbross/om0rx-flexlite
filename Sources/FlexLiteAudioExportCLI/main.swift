import CaptureKit
import Foundation

guard CommandLine.arguments.count >= 5,
      CommandLine.arguments[1] == "--capture",
      let outIndex = CommandLine.arguments.firstIndex(of: "--out"),
      CommandLine.arguments.indices.contains(outIndex + 1) else {
    fputs("Usage: swift run flexlite-audio-export --capture <bundle-path> --out <wav-path> [--stream <stream-id|rx>]\n", stderr)
    exit(1)
}

let captureURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[outIndex + 1])
let streamIndex = CommandLine.arguments.firstIndex(of: "--stream")
let streamValue = streamIndex.flatMap { index in
    CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil
}
let streamID = (streamValue == nil || streamValue == "rx") ? nil : streamValue

try AudioExportService().exportWAV(bundleAt: captureURL, streamID: streamID, outputURL: outputURL)
print("Wrote \(outputURL.path)")
