import Diagnostics
import Foundation
import Vita49

public actor RemoteAudioPipeline {
    public struct Stats: Sendable, Equatable {
        public var bufferDepth: Int
        public var packetLossEstimate: Double
        public var underruns: Int
        public var lastError: String?
        public var payloadsAcceptedByDecoder: Int
        public var decodedPCMFrames: Int
        public var playbackBuffersSubmitted: Int
        public var playbackBuffersRendered: Int

        public init(
            bufferDepth: Int = 0,
            packetLossEstimate: Double = 0,
            underruns: Int = 0,
            lastError: String? = nil,
            payloadsAcceptedByDecoder: Int = 0,
            decodedPCMFrames: Int = 0,
            playbackBuffersSubmitted: Int = 0,
            playbackBuffersRendered: Int = 0
        ) {
            self.bufferDepth = bufferDepth
            self.packetLossEstimate = packetLossEstimate
            self.underruns = underruns
            self.lastError = lastError
            self.payloadsAcceptedByDecoder = payloadsAcceptedByDecoder
            self.decodedPCMFrames = decodedPCMFrames
            self.playbackBuffersSubmitted = playbackBuffersSubmitted
            self.playbackBuffersRendered = playbackBuffersRendered
        }
    }

    public struct ToneTestReport: Sendable, Equatable {
        public var engineStarted: Bool
        public var engineStopped: Bool
        public var outputDeviceName: String
        public var outputSampleRate: Double
        public var channelCount: Int
        public var submittedBufferCount: Int
        public var renderedBufferCount: Int
        public var nonZeroSampleCount: Int
        public var rmsLevel: Double
        public var peakLevel: Double
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
    private var payloadsAcceptedByDecoder = 0
    private var decodedPCMFrames = 0
    private var radioPlaybackSubmissionCount = 0

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
        let playbackTelemetry = playback.telemetrySnapshot()
        return Stats(
            bufferDepth: await buffer.depth(),
            packetLossEstimate: packetLossEstimate,
            underruns: await buffer.underrunCount,
            lastError: lastError,
            payloadsAcceptedByDecoder: payloadsAcceptedByDecoder,
            decodedPCMFrames: decodedPCMFrames,
            playbackBuffersSubmitted: playbackTelemetry.submittedBuffers,
            playbackBuffersRendered: playbackTelemetry.renderedBuffers
        )
    }

    public func reset() async {
        lastSequence = nil
        droppedPackets = 0
        receivedPackets = 0
        lastError = nil
        pendingSamples.removeAll(keepingCapacity: false)
        payloadsAcceptedByDecoder = 0
        decodedPCMFrames = 0
        radioPlaybackSubmissionCount = 0
        playback.stop()
        playback.resetTelemetry()
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

    private func play(_ samples: [Float], source: String) async throws {
        if source == "radio" {
            radioPlaybackSubmissionCount += 1
            if radioPlaybackSubmissionCount.isMultiple(of: 25) {
                await logSampleMeter(label: "RADIO", samples: samples)
            }
        }
        playback.enqueue(samples: samples)
        if !playbackStarted && playback.queuedBufferCount() >= startupQueuedBufferTarget {
            try playback.start()
            playbackStarted = true
        }
    }

    private func drainReadyPacketsForPlayback() async throws {
        while playback.queuedBufferCount() < maximumQueuedBufferTarget, await buffer.depth() > 0 {
            guard let packet = await buffer.pop() else { break }
            let decoded = try decodeSamples(from: packet.payload)
            payloadsAcceptedByDecoder += 1
            decodedPCMFrames += decoded.count
            pendingSamples.append(contentsOf: decoded)
        }

        while pendingSamples.count >= scheduleChunkSamples, playback.queuedBufferCount() < maximumQueuedBufferTarget {
            let chunk = Array(pendingSamples.prefix(scheduleChunkSamples))
            try await play(chunk, source: "radio")
            pendingSamples.removeFirst(scheduleChunkSamples)
        }
    }

    public func playTestTone(outputDeviceName: String) async -> ToneTestReport {
        let sampleRate = 24_000.0
        let frequencyHz = 1_000.0
        let durationSeconds = 2.0
        let amplitude: Float = 0.25
        let totalSamples = Int(sampleRate * durationSeconds)
        let chunkSize = 2_048

        playback.stop()
        playback.resetTelemetry()
        playbackStarted = false

        var samples: [Float] = []
        samples.reserveCapacity(totalSamples)
        var nonZeroSampleCount = 0
        var squared: Double = 0
        var peak: Float = 0

        for index in 0..<totalSamples {
            let value = amplitude * sin(Float(2 * Double.pi * frequencyHz * Double(index) / sampleRate))
            samples.append(value)
            if value != 0 {
                nonZeroSampleCount += 1
            }
            squared += Double(value * value)
            peak = max(peak, abs(value))
        }

        var engineStarted = false
        var engineStopped = false

        do {
            await logSampleMeter(label: "TEST_TONE", samples: samples)
            for offset in stride(from: 0, to: samples.count, by: chunkSize) {
                let end = min(offset + chunkSize, samples.count)
                try await play(Array(samples[offset..<end]), source: "test-tone")
            }
            let startedTelemetry = playback.telemetrySnapshot()
            engineStarted = startedTelemetry.engineRunning || startedTelemetry.playerRunning
            try? await Task.sleep(for: .milliseconds(2_400))
            playback.stop()
            engineStopped = true
            playbackStarted = false
        } catch {
            lastError = error.localizedDescription
        }

        let telemetry = playback.telemetrySnapshot()
        let rms = samples.isEmpty ? 0 : sqrt(squared / Double(samples.count))
        return ToneTestReport(
            engineStarted: engineStarted,
            engineStopped: engineStopped,
            outputDeviceName: outputDeviceName,
            outputSampleRate: telemetry.sampleRate,
            channelCount: telemetry.channelCount,
            submittedBufferCount: telemetry.submittedBuffers,
            renderedBufferCount: telemetry.renderedBuffers,
            nonZeroSampleCount: nonZeroSampleCount,
            rmsLevel: rms,
            peakLevel: Double(peak)
        )
    }

    private func logSampleMeter(label: String, samples: [Float]) async {
        guard let diagnostics else { return }
        guard !samples.isEmpty else { return }

        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        var sumSquares: Double = 0
        var nonZero = 0
        var peak: Float = 0

        for sample in samples {
            minValue = min(minValue, sample)
            maxValue = max(maxValue, sample)
            let absolute = abs(sample)
            peak = max(peak, absolute)
            if absolute > 0 {
                nonZero += 1
            }
            sumSquares += Double(sample * sample)
        }

        let rms = sqrt(sumSquares / Double(samples.count))
        let first16 = samples.prefix(16).map { String(format: "%.6f", $0) }.joined(separator: ",")
        await diagnostics.log(.info, "\(label) PCM meter", metadata: [
            "min": String(format: "%.6f", minValue),
            "max": String(format: "%.6f", maxValue),
            "rms": String(format: "%.6f", rms),
            "peak": String(format: "%.6f", peak),
            "non_zero": "\(nonZero)",
            "first16": first16
        ])
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
