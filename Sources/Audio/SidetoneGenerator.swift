import AVFoundation
import Foundation

public final class SidetoneGenerator: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sampleRate: Double = 48_000
    private var phase = 0.0
    private var sourceNode: AVAudioSourceNode?

    public private(set) var frequency: Double
    public private(set) var amplitude: Double

    public init(frequency: Double = 600, amplitude: Double = 0.15) {
        self.frequency = frequency
        self.amplitude = amplitude
    }

    public func configure(frequency: Double, amplitude: Double) {
        self.frequency = frequency
        self.amplitude = amplitude
    }

    public func start() throws {
        guard sourceNode == nil else { return }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = 2.0 * Double.pi * self.frequency / self.sampleRate

            for frameIndex in 0..<Int(frameCount) {
                let sample = Float(sin(self.phase) * self.amplitude)
                self.phase += phaseIncrement
                if self.phase >= 2.0 * Double.pi {
                    self.phase -= 2.0 * Double.pi
                }

                for buffer in ablPointer {
                    let channel = buffer.mData?.assumingMemoryBound(to: Float.self)
                    channel?[frameIndex] = sample
                }
            }

            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    public func stop() {
        engine.stop()
        if let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
    }
}
