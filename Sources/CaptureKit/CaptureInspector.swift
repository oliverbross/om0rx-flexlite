import Foundation
import Vita49

public struct CaptureInspectionReport: Sendable {
    public var lines: [String]

    public init(lines: [String]) {
        self.lines = lines
    }

    public var rendered: String {
        lines.joined(separator: "\n")
    }
}

public struct CaptureInspector {
    private let loader = CaptureBundleLoader()
    private let parser = VitaParser()

    public init() {}

    public func inspect(bundleAt url: URL) throws -> CaptureInspectionReport {
        let bundle = try loader.loadBundle(at: url)
        var lines: [String] = []
        lines.append("Bundle: \(url.path)")
        lines.append("Session: \(bundle.sessionMetadata.sessionName)")
        lines.append("Control entries: \(bundle.controlEntries.count)")
        lines.append("UDP entries: \(bundle.udpEntries.count)")

        let timeline = Dictionary(grouping: bundle.udpEntries, by: { $0.streamID ?? "unknown" })
        for (streamID, entries) in timeline.sorted(by: { $0.key < $1.key }) {
            let gaps = sequenceGapCount(entries)
            let payloadGuess = entries.first.flatMap { guessPayloadType(data: loader.frameData(for: $0, in: bundle)) } ?? "unknown"
            lines.append("Stream \(streamID): \(entries.count) frames, sequence gaps=\(gaps), payload=\(payloadGuess)")
        }

        lines.append("First control timeline:")
        for entry in bundle.controlEntries.prefix(10) {
            lines.append("  \(entry.timestamp.ISO8601Format()) \(entry.direction.rawValue) \(entry.classification.rawValue) \(entry.rawLine)")
        }

        return CaptureInspectionReport(lines: lines)
    }

    public func loadBundle(at url: URL) throws -> CaptureBundle {
        try loader.loadBundle(at: url)
    }

    private func sequenceGapCount(_ entries: [UDPLogEntry]) -> Int {
        let sequences = entries.compactMap(\.sequence).sorted()
        guard sequences.count > 1 else { return 0 }
        var gaps = 0
        for pair in zip(sequences, sequences.dropFirst()) where pair.1 != pair.0 + 1 {
            gaps += 1
        }
        return gaps
    }

    private func guessPayloadType(data: Data) -> String {
        if let packet = try? parser.parse(data) {
            if packet.payload.count.isMultiple(of: 2) {
                return "pcm16-candidate"
            }
            return "compressed-or-opaque"
        }
        return "unparsed"
    }
}
