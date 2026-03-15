import Foundation
import Vita49

public struct AudioExportService {
    private let loader = CaptureBundleLoader()
    private let parser = VitaParser()

    public init() {}

    public func exportWAV(
        bundleAt url: URL,
        streamID: String?,
        assumption: AudioExportAssumption = .pcm16Mono24k,
        outputURL: URL
    ) throws {
        let bundle = try loader.loadBundle(at: url)
        let targetStream = streamID ?? bundle.udpEntries.compactMap(\.streamID).first
        let frames = bundle.udpEntries.filter { targetStream == nil || $0.streamID == targetStream }

        var pcm = Data()
        for entry in frames {
            let datagram = loader.frameData(for: entry, in: bundle)
            guard let packet = try? parser.parse(datagram) else { continue }
            switch assumption {
            case .pcm16Mono24k:
                pcm.append(packet.payload)
            }
        }

        try writePCM16MonoWAV(pcmData: pcm, sampleRate: 24_000, to: outputURL)
    }

    private func writePCM16MonoWAV(pcmData: Data, sampleRate: UInt32, to url: URL) throws {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let chunkSize = 36 + UInt32(pcmData.count)

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(littleEndian(chunkSize))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(littleEndian(UInt32(16)))
        wav.append(littleEndian(UInt16(1)))
        wav.append(littleEndian(channels))
        wav.append(littleEndian(sampleRate))
        wav.append(littleEndian(byteRate))
        wav.append(littleEndian(blockAlign))
        wav.append(littleEndian(bitsPerSample))
        wav.append("data".data(using: .ascii)!)
        wav.append(littleEndian(UInt32(pcmData.count)))
        wav.append(pcmData)
        try wav.write(to: url)
    }

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}
