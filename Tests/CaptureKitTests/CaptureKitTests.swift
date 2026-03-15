import CaptureKit
import Foundation
import Testing
import Vita49

private actor SeenEvents {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

@Test
func recordsAndLoadsCaptureBundle() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

    let recorder = try CaptureRecorder(
        baseURL: temp,
        context: CaptureContext(
            sessionName: "unit-test",
            manifest: CaptureBundleManifest(appVersion: "test", osVersion: "macOS", connectionMode: "manualHost", rxAudioEnabled: true, txAudioEnabled: false, cwxUsed: false, ctr2Attached: false),
            sessionMetadata: CaptureSessionMetadata(sessionName: "unit-test", host: "127.0.0.1", tcpPort: 4992, udpPort: 4994),
            operatorSettings: OperatorSettingsSnapshot(values: ["wanProfile": "WAN SSB"])
        )
    )

    try await recorder.recordControl(direction: .outbound, rawLine: "C1|ping")
    let packet = VitaPacket(streamIdentifier: 0x84000001, sequence: 1, timestamp: 1, payload: Data([0x01, 0x02, 0x03, 0x04]))
    try await recorder.recordUDP(datagram: VitaWriter().encode(packet))
    try await recorder.finish(notes: "unit")

    let bundle = try CaptureBundleLoader().loadBundle(at: recorder.bundleURL)
    #expect(bundle.controlEntries.count == 1)
    #expect(bundle.udpEntries.count == 1)
    #expect(bundle.udpFrames.count > 0)
}

@Test
func exportsWavFromSyntheticCapture() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

    let recorder = try CaptureRecorder(
        baseURL: temp,
        context: CaptureContext(
            sessionName: "audio-test",
            manifest: CaptureBundleManifest(appVersion: "test", osVersion: "macOS", connectionMode: "manualHost", rxAudioEnabled: true, txAudioEnabled: false, cwxUsed: false, ctr2Attached: false),
            sessionMetadata: CaptureSessionMetadata(sessionName: "audio-test", host: "127.0.0.1", tcpPort: 4992, udpPort: 4994),
            operatorSettings: OperatorSettingsSnapshot(values: [:])
        )
    )

    let pcmPayload = Data([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0x00, 0x00])
    let packet = VitaPacket(streamIdentifier: 0x84000002, sequence: 1, timestamp: 1, payload: pcmPayload)
    try await recorder.recordUDP(datagram: VitaWriter().encode(packet))
    try await recorder.finish()

    let output = temp.appendingPathComponent("out.wav")
    try AudioExportService().exportWAV(bundleAt: recorder.bundleURL, streamID: "0x84000002", outputURL: output)
    let wav = try Data(contentsOf: output)
    #expect(wav.starts(with: Data("RIFF".utf8)))
}

@Test
func replaysCapturedEventsInBurstOrder() async throws {
    let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

    let recorder = try CaptureRecorder(
        baseURL: temp,
        context: CaptureContext(
            sessionName: "replay-test",
            manifest: CaptureBundleManifest(appVersion: "test", osVersion: "macOS", connectionMode: "manualHost", rxAudioEnabled: true, txAudioEnabled: false, cwxUsed: false, ctr2Attached: false),
            sessionMetadata: CaptureSessionMetadata(sessionName: "replay-test", host: "127.0.0.1", tcpPort: 4992, udpPort: 4994),
            operatorSettings: OperatorSettingsSnapshot(values: [:])
        )
    )

    try await recorder.recordControl(direction: .outbound, rawLine: "C1|ping")
    let packet = VitaPacket(streamIdentifier: 0x84000003, sequence: 7, timestamp: 1, payload: Data([0xAA, 0xBB]))
    try await recorder.recordUDP(datagram: VitaWriter().encode(packet))
    try await recorder.finish()

    let seen = SeenEvents()
    try await CaptureReplayer().replay(bundleAt: recorder.bundleURL, speed: .burst) { event in
        switch event {
        case .control:
            await seen.append("control")
        case .udp:
            await seen.append("udp")
        }
    }

    let snapshot = await seen.snapshot()
    #expect(snapshot.contains("control"))
    #expect(snapshot.contains("udp"))
}
