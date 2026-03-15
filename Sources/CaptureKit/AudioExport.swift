import Foundation
import Vita49

public struct AudioExportService {
    private let loader = CaptureBundleLoader()
    private let parser = VitaParser()

    public init() {}

    public func exportWAV(
        bundleAt url: URL,
        streamID: String?,
        assumption: AudioExportAssumption = .auto,
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
            case .auto:
                pcm.append(convertPayloadToPCM16(packet.payload))
            case .pcm16Mono24k:
                pcm.append(packet.payload)
            case .pcmFloat32Mono24k:
                pcm.append(convertFloat32Payload(packet.payload, channelMode: .mono))
            case .pcmFloat32Stereo24k:
                pcm.append(convertFloat32Payload(packet.payload, channelMode: .stereoInterleaved))
            }
        }

        try writePCM16MonoWAV(pcmData: pcm, sampleRate: 24_000, to: outputURL)
    }

    private enum Float32ChannelMode {
        case mono
        case stereoInterleaved
    }

    private func convertPayloadToPCM16(_ payload: Data) -> Data {
        if payload.count.isMultiple(of: 4), looksLikeFloat32Payload(payload) {
            return convertFloat32Payload(payload, channelMode: .stereoInterleaved)
        }
        if payload.count.isMultiple(of: 2) {
            return payload
        }
        return Data()
    }

    private func looksLikeFloat32Payload(_ payload: Data) -> Bool {
        guard payload.count >= 16 else { return false }
        var finiteCount = 0
        let probeWords = min(payload.count / 4, 64)
        for index in 0..<probeWords {
            let offset = index * 4
            let word = payload[offset..<offset + 4].reduce(into: UInt32.zero) { partial, byte in
                partial = (partial << 8) | UInt32(byte)
            }
            let value = Float(bitPattern: word)
            if value.isFinite {
                finiteCount += 1
            }
        }
        return finiteCount >= probeWords * 3 / 4
    }

    private func convertFloat32Payload(_ payload: Data, channelMode: Float32ChannelMode) -> Data {
        guard payload.count.isMultiple(of: 4) else { return Data() }
        var pcm16 = Data()
        pcm16.reserveCapacity(payload.count / 2)

        let stride = channelMode == .mono ? 4 : 8
        var offset = 0
        while offset + 4 <= payload.count {
            let word = payload[offset..<offset + 4].reduce(into: UInt32.zero) { partial, byte in
                partial = (partial << 8) | UInt32(byte)
            }
            let sample = Float(bitPattern: word)
            let clamped = max(-1.0, min(1.0, sample))
            let int16Value = Int16(clamped * Float(Int16.max))
            var little = int16Value.littleEndian
            pcm16.append(Data(bytes: &little, count: MemoryLayout<Int16>.size))
            offset += stride
        }

        return pcm16
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
