import CaptureKit
import Foundation

guard CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--capture" else {
    fputs("Usage: swift run flexlite-inspect --capture <bundle-path>\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let report = try CaptureInspector().inspect(bundleAt: url)
print(report.rendered)
