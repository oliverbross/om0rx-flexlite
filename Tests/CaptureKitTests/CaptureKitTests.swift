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

private let fixtureBundleURL = URL(fileURLWithPath: "/Users/oliver/Documents/FlexLite/CaptureBundles/20260315-023625", isDirectory: true)

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

@Test
func fixtureBundleShowsSilentRemoteAudioStream() throws {
    #expect(FileManager.default.fileExists(atPath: fixtureBundleURL.path))
    let loader = CaptureBundleLoader()
    let parser = VitaParser()
    let bundle = try loader.loadBundle(at: fixtureBundleURL)

    let rxEntries = bundle.udpEntries.filter { $0.streamID == "0x04000009" }
    #expect(!rxEntries.isEmpty)

    var payloadByteCount = 0
    var nonZeroPayloadByteCount = 0
    for entry in rxEntries {
        let datagram = loader.frameData(for: entry, in: bundle)
        let packet = try parser.parse(datagram)
        payloadByteCount += packet.payload.count
        nonZeroPayloadByteCount += packet.payload.reduce(into: 0) { count, byte in
            if byte != 0 { count += 1 }
        }
    }

    #expect(payloadByteCount > 0)
    #expect(nonZeroPayloadByteCount == 0)

    let wav = try Data(contentsOf: fixtureBundleURL.appendingPathComponent("rx.wav"))
    #expect(wav.count > 44)
    let pcm = wav.dropFirst(44)
    #expect(!pcm.isEmpty)
    #expect(pcm.allSatisfy { $0 == 0 })
}

@Test
func fixtureBundleShowsAudioClientAddFailureBeforeRxStreamAck() throws {
    #expect(FileManager.default.fileExists(atPath: fixtureBundleURL.path))
    let bundle = try CaptureBundleLoader().loadBundle(at: fixtureBundleURL)

    let outbound = bundle.controlEntries.filter { $0.direction == .outbound }
    let inbound = bundle.controlEntries.filter { $0.direction == .inbound }

    let clientGUIEntry = try #require(outbound.first(where: { $0.rawLine.contains("|client gui ") }))
    let addEntry = try #require(outbound.first(where: { $0.rawLine.contains("|audio client ") && $0.rawLine.contains(" slice 1 add") }))
    let streamCreateEntry = try #require(outbound.first(where: { $0.rawLine.contains("|stream create type=remote_audio_rx compression=none") }))

    let addSequence = try #require(sequenceID(fromCommandLine: addEntry.rawLine))
    let streamCreateSequence = try #require(sequenceID(fromCommandLine: streamCreateEntry.rawLine))

    let addResponse = try #require(inbound.first(where: { sequenceID(fromResponseLine: $0.rawLine) == addSequence }))
    let streamCreateResponse = try #require(inbound.first(where: { sequenceID(fromResponseLine: $0.rawLine) == streamCreateSequence }))

    #expect(addEntry.timestamp < streamCreateResponse.timestamp)
    #expect(responseCode(fromResponseLine: addResponse.rawLine) == 0x50001000)
    #expect(outbound.allSatisfy { !$0.rawLine.contains("remote_audio rx_on on") })

    let clientID = clientGUIEntry.rawLine.split(separator: " ").last.map(String.init)
    #expect(clientID != nil)
    if let clientID {
        #expect(addEntry.rawLine.contains(clientID))
    }
}

@Test
func fixtureBundleUsesOrderedModuloSequenceGapAccounting() throws {
    #expect(FileManager.default.fileExists(atPath: fixtureBundleURL.path))
    let report = try CaptureInspector().inspect(bundleAt: fixtureBundleURL).rendered

    #expect(report.contains("Stream 0x04000009: 13355 frames, sequence gaps=251"))
    #expect(!report.contains("sequence gaps=13339"))
}

private func sequenceID(fromCommandLine line: String) -> Int? {
    guard line.hasPrefix("C"), let delimiter = line.firstIndex(of: "|") else { return nil }
    return Int(line[line.index(after: line.startIndex)..<delimiter])
}

private func sequenceID(fromResponseLine line: String) -> Int? {
    guard line.hasPrefix("R"), let delimiter = line.firstIndex(of: "|") else { return nil }
    return Int(line[line.index(after: line.startIndex)..<delimiter])
}

private func responseCode(fromResponseLine line: String) -> UInt32? {
    guard line.hasPrefix("R") else { return nil }
    let components = line.split(separator: "|", omittingEmptySubsequences: false)
    guard components.count >= 2 else { return nil }
    return UInt32(components[1], radix: 16)
}
