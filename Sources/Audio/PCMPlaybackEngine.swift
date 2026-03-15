import AVFoundation
import AudioUnit
import Foundation

public final class PCMPlaybackEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let stateLock = NSLock()
    private var scheduledBufferCount = 0

    public init(sampleRate: Double = 24_000, channels: AVAudioChannelCount = 1) {
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) ?? AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    public func start() throws {
        if !engine.isRunning {
            try engine.start()
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    public func stop() {
        playerNode.stop()
        engine.stop()
        stateLock.lock()
        scheduledBufferCount = 0
        stateLock.unlock()
    }

    public func setGain(_ value: Float) {
        playerNode.volume = max(0, min(value, 1))
    }

    public func setOutputDevice(_ deviceID: String?) throws {
        guard let deviceID, let rawDeviceID = UInt32(deviceID) else { return }
        var selectedDeviceID = AudioDeviceID(rawDeviceID)
        let status = AudioUnitSetProperty(
            engine.outputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw PlaybackEngineError.outputDeviceSelectionFailed(status)
        }
    }

    public func enqueue(samples: [Float]) {
        guard !samples.isEmpty else { return }
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        let pointer = buffer.floatChannelData?[0]
        pointer?.update(from: samples, count: samples.count)
        stateLock.lock()
        scheduledBufferCount += 1
        stateLock.unlock()
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.stateLock.lock()
            self.scheduledBufferCount = max(0, self.scheduledBufferCount - 1)
            self.stateLock.unlock()
        }
    }

    public func queuedBufferCount() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return scheduledBufferCount
    }
}

public enum PlaybackEngineError: LocalizedError {
    case outputDeviceSelectionFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .outputDeviceSelectionFailed(let status):
            return "Unable to select output device (OSStatus \(status))"
        }
    }
}
