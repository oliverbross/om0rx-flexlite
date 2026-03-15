import CaptureKit
import Foundation

guard CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--capture" else {
    fputs("Usage: swift run flexlite-replay --capture <bundle-path> [--mode realtime|half|burst|step]\n", stderr)
    exit(1)
}

let captureURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let modeIndex = CommandLine.arguments.firstIndex(of: "--mode")
let speed = modeIndex.flatMap { index in
    CommandLine.arguments.indices.contains(index + 1) ? ReplaySpeed(rawValue: CommandLine.arguments[index + 1]) : nil
} ?? .burst

try await CaptureReplayer().replay(bundleAt: captureURL, speed: speed) { event in
    switch event {
    case .control(let entry):
        print("[CTRL] \(entry.timestamp.ISO8601Format()) \(entry.direction.rawValue) \(entry.rawLine)")
    case .udp(let entry, _):
        print("[UDP]  \(entry.timestamp.ISO8601Format()) len=\(entry.length) stream=\(entry.streamID ?? "?") seq=\(entry.sequence.map(String.init) ?? "?")")
    }
}
