import AVFoundation
import Foundation

public final class MicrophoneCaptureEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let desiredFrames: AVAudioFrameCount
    private let onSamples: @Sendable ([Float], Double) -> Void
    private var isCapturing = false

    public init(bufferSize: AVAudioFrameCount = 480, onSamples: @escaping @Sendable ([Float], Double) -> Void) {
        self.desiredFrames = bufferSize
        self.onSamples = onSamples
    }

    public func start() throws {
        guard !isCapturing else { return }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: desiredFrames, format: format) { [onSamples] buffer, _ in
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            if let floats = buffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: floats, count: frameLength))
                onSamples(samples, format.sampleRate)
            }
        }

        try engine.start()
        isCapturing = true
    }

    public func stop() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }
}
