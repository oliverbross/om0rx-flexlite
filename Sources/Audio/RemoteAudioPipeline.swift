import Diagnostics
import Foundation
import Vita49

public actor RemoteAudioPipeline {
    public struct Stats: Sendable, Equatable {
        public var bufferDepth: Int
        public var packetLossEstimate: Double
        public var underruns: Int
        public var lastError: String?

        public init(bufferDepth: Int = 0, packetLossEstimate: Double = 0, underruns: Int = 0, lastError: String? = nil) {
            self.bufferDepth = bufferDepth
            self.packetLossEstimate = packetLossEstimate
            self.underruns = underruns
            self.lastError = lastError
        }
    }

    private let buffer: AdaptiveJitterBuffer<VitaPacket>
    private let diagnostics: DiagnosticsCenter?
    private let playback = PCMPlaybackEngine()
    private let minimumBufferedPackets = 10
    private let scheduleChunkSamples = 2_048
    private let startupQueuedBufferTarget = 3
    private let maximumQueuedBufferTarget = 8
    private var lastSequence: UInt16?
    private var droppedPackets = 0
    private var receivedPackets = 0
    private var playbackStarted = false
    private var lastError: String?
    private var pendingSamples: [Float] = []

    public init(capacity: Int = 64, diagnostics: DiagnosticsCenter? = nil) {
        self.buffer = AdaptiveJitterBuffer<VitaPacket>(capacity: capacity)
        self.diagnostics = diagnostics
    }

    public func receive(_ packet: VitaPacket) async {
        if let lastSequence {
            let expected = (lastSequence + 1) & 0x000F
            if packet.sequence != expected {
                let delta = Int((packet.sequence &+ 16 &- expected) & 0x000F)
                droppedPackets += delta == 0 ? 1 : delta
            }
        }

        lastSequence = packet.sequence
        receivedPackets += 1
        await buffer.push(packet)

        let depth = await buffer.depth()
        let queuedPlaybackBuffers = playback.queuedBufferCount()
        guard depth >= minimumBufferedPackets || !pendingSamples.isEmpty || queuedPlaybackBuffers < startupQueuedBufferTarget else { return }

        do {
            try await drainReadyPacketsForPlayback()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if let diagnostics {
                await diagnostics.log(.error, "Audio playback failed", metadata: ["error": error.localizedDescription])
            }
        }
    }

    public func nextPacket() async -> VitaPacket? {
        await buffer.pop()
    }

    public func stats() async -> Stats {
        let packetLossEstimate = receivedPackets == 0 ? 0 : Double(max(droppedPackets, 0)) / Double(receivedPackets)
        return Stats(
            bufferDepth: await buffer.depth(),
            packetLossEstimate: packetLossEstimate,
            underruns: await buffer.underrunCount,
            lastError: lastError
        )
    }

    public func reset() async {
        lastSequence = nil
        droppedPackets = 0
        receivedPackets = 0
        lastError = nil
        pendingSamples.removeAll(keepingCapacity: false)
        playback.stop()
        playbackStarted = false
        await buffer.reset()
    }

    public func setOutputDevice(_ deviceID: String?) async {
        do {
            try playback.setOutputDevice(deviceID)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func play(_ samples: [Float]) throws {
        playback.enqueue(samples: samples)
        if !playbackStarted && playback.queuedBufferCount() >= startupQueuedBufferTarget {
            try playback.start()
            playbackStarted = true
        }
    }

    private func drainReadyPacketsForPlayback() async throws {
        while playback.queuedBufferCount() < maximumQueuedBufferTarget, await buffer.depth() > 0 {
            guard let packet = await buffer.pop() else { break }
            pendingSamples.append(contentsOf: try decodeSamples(from: packet.payload))
        }

        while pendingSamples.count >= scheduleChunkSamples, playback.queuedBufferCount() < maximumQueuedBufferTarget {
            let chunk = Array(pendingSamples.prefix(scheduleChunkSamples))
            try play(chunk)
            pendingSamples.removeFirst(scheduleChunkSamples)
        }
    }

    private func decodeSamples(from payload: Data) throws -> [Float] {
        guard payload.count.isMultiple(of: 4) else {
            throw AudioPipelineError.invalidPCMFrameLength(payload.count)
        }

        var samples: [Float] = []
        samples.reserveCapacity(payload.count / 4)

        for offset in stride(from: 0, to: payload.count, by: 4) {
            let word = payload[offset..<offset + 4].reduce(into: UInt32.zero) { partial, byte in
                partial = (partial << 8) | UInt32(byte)
            }
            samples.append(Float(bitPattern: word))
        }

        guard samples.count >= 2, samples.count.isMultiple(of: 2) else {
            return samples
        }

        let probePairs = min(samples.count / 2, 32)
        let duplicatePairs = (0..<probePairs).reduce(into: 0) { count, index in
            if abs(samples[index * 2] - samples[index * 2 + 1]) < 0.000_001 {
                count += 1
            }
        }

        guard duplicatePairs >= probePairs - 1 else {
            return samples
        }

        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(samples.count / 2)
        for index in stride(from: 0, to: samples.count, by: 2) {
            monoSamples.append(samples[index])
        }
        return monoSamples
    }
}

public enum AudioPipelineError: LocalizedError {
    case invalidPCMFrameLength(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidPCMFrameLength(let length):
            return "Unexpected RX audio payload length: \(length) bytes"
        }
    }
}
