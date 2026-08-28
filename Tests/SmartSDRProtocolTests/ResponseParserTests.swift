import SmartSDRProtocol
import Testing

@Test
func parsesVersionAndHandleLines() {
    let parser = ResponseParser()

    #expect(parser.parse(line: "V3.10.15.1") == .version("3.10.15.1"))
    #expect(parser.parse(line: "H12345678") == .handle("12345678"))
}

@Test
func parsesStatusPayloadIntoProperties() {
    let parser = ResponseParser()
    let message = parser.parse(line: "S0|slice 0 RF_frequency=14.074000 mode=USB tx=1")

    guard case .status(let status) = message else {
        Issue.record("Expected status message")
        return
    }

    #expect(status.handle == "0")
    #expect(status.object == "slice")
    #expect(status.identifier == "0")
    #expect(status.properties["RF_frequency"] == "14.074000")
    #expect(status.properties["mode"] == "USB")
}

@Test
func encodesBootstrapCommands() {
    let encoder = CommandEncoder()
    let commands = encoder.remoteAudioCommands(profile: RemoteAudioProfile(
        compression: .none,
        bitrate: 16000,
        bufferSize: 240,
        bandwidth: 800,
        maxBandwidth: 1000,
        complexity: 4,
        rxEnabled: true,
        txAudioEnabled: false
    ))

    #expect(commands == ["stream create type=remote_audio_rx compression=none"])
    #expect(encoder.createRemoteAudioRXStream(compression: .none) == "stream create type=remote_audio_rx compression=none")
    #expect(encoder.remoteAudioRXOn(true) == "remote_audio rx_on on")
    #expect(encoder.wrap(body: "ping", sequence: 42) == "C42|ping")
}

@Test
func parsesRemoteAudioStreamStatus() {
    let parser = ResponseParser()
    let message = parser.parse(line: "S7289A5F4|stream 0x04000008 type=remote_audio_rx compression=NONE client_handle=0x7289A5F4 ip=10.8.0.6")

    guard case .status(let status) = message else {
        Issue.record("Expected status message")
        return
    }

    #expect(status.object == "stream")
    #expect(status.identifier == "0x04000008")
    #expect(status.properties["type"] == "remote_audio_rx")
    #expect(status.properties["compression"] == "NONE")
}

@Test
func parsesInterlockTransmitFields() {
    let parser = ResponseParser()
    let message = parser.parse(line: "S41F4592A|interlock tx_client_handle=0x1336E697 state=TRANSMITTING reason=TUNE source= tx_allowed=1 amplifier=")

    guard case .status(let status) = message else {
        Issue.record("Expected status message")
        return
    }

    #expect(status.object == "interlock")
    #expect(status.properties["tx_client_handle"] == "0x1336E697")
    #expect(status.properties["state"] == "TRANSMITTING")
    #expect(status.properties["reason"] == "TUNE")
    #expect(status.properties["tx_allowed"] == "1")
}
