import Foundation
import SmartSDRProtocol
import Vita49

public struct CaptureContext: Sendable {
    public var sessionName: String
    public var manifest: CaptureBundleManifest
    public var sessionMetadata: CaptureSessionMetadata
    public var operatorSettings: OperatorSettingsSnapshot

    public init(sessionName: String, manifest: CaptureBundleManifest, sessionMetadata: CaptureSessionMetadata, operatorSettings: OperatorSettingsSnapshot) {
        self.sessionName = sessionName
        self.manifest = manifest
        self.sessionMetadata = sessionMetadata
        self.operatorSettings = operatorSettings
    }
}

public actor CaptureRecorder {
    private let rootURL: URL
    private let controlHandle: FileHandle
    private let udpHandle: FileHandle
    private let frameHandle: FileHandle
    private let encoder = JSONEncoder()
    private var manifest: CaptureBundleManifest
    private var sessionMetadata: CaptureSessionMetadata
    private var operatorSettings: OperatorSettingsSnapshot
    private var frameOffset = 0
    private var udpFramesWritten = 0

    public nonisolated let bundleURL: URL

    public init(baseURL: URL, context: CaptureContext) throws {
        encoder.dateEncodingStrategy = .iso8601
        manifest = context.manifest
        sessionMetadata = context.sessionMetadata
        operatorSettings = context.operatorSettings

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let bundleName = formatter.string(from: .now)

        rootURL = baseURL
        bundleURL = baseURL.appendingPathComponent(bundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let controlURL = bundleURL.appendingPathComponent("control-log.ndjson")
        let udpURL = bundleURL.appendingPathComponent("udp-log.ndjson")
        let framesURL = bundleURL.appendingPathComponent("udp-frames.bin")
        FileManager.default.createFile(atPath: controlURL.path(), contents: nil)
        FileManager.default.createFile(atPath: udpURL.path(), contents: nil)
        FileManager.default.createFile(atPath: framesURL.path(), contents: nil)
        controlHandle = try FileHandle(forWritingTo: controlURL)
        udpHandle = try FileHandle(forWritingTo: udpURL)
        frameHandle = try FileHandle(forWritingTo: framesURL)

        try Self.writeJSON(manifest, to: bundleURL.appendingPathComponent("manifest.json"))
        try controlHandle.synchronize()
        try udpHandle.synchronize()
        try frameHandle.synchronize()
        try Self.writeJSON(sessionMetadata, to: bundleURL.appendingPathComponent("session-metadata.json"))
        try Self.writeJSON(operatorSettings, to: bundleURL.appendingPathComponent("operator-settings.json"))
        try Data().write(to: bundleURL.appendingPathComponent("notes.txt"))
    }

    deinit {
        try? controlHandle.close()
        try? udpHandle.close()
        try? frameHandle.close()
    }

    public func recordControl(direction: CaptureDirection, rawLine: String) throws {
        let entry = ControlLogEntry(direction: direction, rawLine: rawLine, classification: classifyControlLine(rawLine))
        try appendNDJSON(entry, handle: controlHandle)
    }

    public func recordUDP(datagram: Data, source: String? = nil, destination: String? = nil) throws {
        let parser = VitaParser()
        let summary: String
        let streamID: String?
        let sequence: Int?

        if let packet = try? parser.parse(datagram) {
            summary = "stream=\(String(format: "0x%08X", packet.streamIdentifier)) seq=\(packet.sequence) payload=\(packet.payload.count)"
            streamID = String(format: "0x%08X", packet.streamIdentifier)
            sequence = Int(packet.sequence)
        } else {
            summary = "unparsed length=\(datagram.count)"
            streamID = nil
            sequence = nil
        }

        try frameHandle.seekToEnd()
        try frameHandle.write(contentsOf: datagram)
        udpFramesWritten += 1
        let entry = UDPLogEntry(
            length: datagram.count,
            offset: frameOffset,
            source: source,
            destination: destination,
            streamID: streamID,
            sequence: sequence,
            summary: summary
        )
        frameOffset += datagram.count
        try appendNDJSON(entry, handle: udpHandle)
    }

    public func finish(notes: String = "") throws {
        try notes.data(using: .utf8)?.write(to: bundleURL.appendingPathComponent("notes.txt"))
        try flushManifest()
        try controlHandle.synchronize()
        try udpHandle.synchronize()
        try frameHandle.synchronize()
    }

    public func flushManifest() throws {
        try Self.writeJSON(manifest, to: bundleURL.appendingPathComponent("manifest.json"))
        try controlHandle.synchronize()
        try udpHandle.synchronize()
        try frameHandle.synchronize()
    }

    public func udpFrameCount() -> Int {
        udpFramesWritten
    }

    private func appendNDJSON<T: Encodable>(_ value: T, handle: FileHandle) throws {
        let data = try encoder.encode(value)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.write(contentsOf: Data([0x0A]))
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url)
    }

    private func classifyControlLine(_ rawLine: String) -> ControlClassification {
        switch rawLine.first {
        case "C": return .command
        case "R": return .response
        case "S": return .status
        case "M": return .message
        case "V": return .version
        case "H": return .handle
        default: return .unknown
        }
    }
}
