import Foundation

public enum CaptureBundleError: Error {
    case missingFile(String)
}

public struct CaptureBundleLoader {
    private let decoder: JSONDecoder

    public init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadBundle(at rootURL: URL) throws -> CaptureBundle {
        let manifest = try decode(CaptureBundleManifest.self, at: rootURL.appendingPathComponent("manifest.json"))
        let sessionMetadata = try decode(CaptureSessionMetadata.self, at: rootURL.appendingPathComponent("session-metadata.json"))
        let operatorSettings = try decode(OperatorSettingsSnapshot.self, at: rootURL.appendingPathComponent("operator-settings.json"))
        let controlEntries = try decodeNDJSON(ControlLogEntry.self, at: rootURL.appendingPathComponent("control-log.ndjson"))
        let udpEntries = try decodeNDJSON(UDPLogEntry.self, at: rootURL.appendingPathComponent("udp-log.ndjson"))
        let frameURL = rootURL.appendingPathComponent("udp-frames.bin")
        guard FileManager.default.fileExists(atPath: frameURL.path()) else {
            throw CaptureBundleError.missingFile("udp-frames.bin")
        }
        let udpFrames = try Data(contentsOf: frameURL)
        return CaptureBundle(
            rootURL: rootURL,
            manifest: manifest,
            sessionMetadata: sessionMetadata,
            operatorSettings: operatorSettings,
            controlEntries: controlEntries,
            udpEntries: udpEntries,
            udpFrames: udpFrames
        )
    }

    public func frameData(for entry: UDPLogEntry, in bundle: CaptureBundle) -> Data {
        let end = entry.offset + entry.length
        guard end <= bundle.udpFrames.count else { return Data() }
        return bundle.udpFrames.subdata(in: entry.offset..<end)
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path()) else {
            throw CaptureBundleError.missingFile(url.lastPathComponent)
        }
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func decodeNDJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path()) else {
            return []
        }
        return try String(contentsOf: url)
            .split(whereSeparator: \.isNewline)
            .map { try decoder.decode(T.self, from: Data($0.utf8)) }
    }
}
