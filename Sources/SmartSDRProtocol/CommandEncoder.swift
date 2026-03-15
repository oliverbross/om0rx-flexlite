import Foundation

public enum RemoteAudioCompression: String, Codable, CaseIterable, Sendable, Hashable {
    case none
    case opus
}

public struct RemoteAudioProfile: Codable, Sendable, Equatable, Hashable {
    public var compression: RemoteAudioCompression
    public var bitrate: Int
    public var bufferSize: Int
    public var bandwidth: Int
    public var maxBandwidth: Int
    public var complexity: Int
    public var rxEnabled: Bool
    public var txAudioEnabled: Bool

    public init(
        compression: RemoteAudioCompression = .opus,
        bitrate: Int,
        bufferSize: Int,
        bandwidth: Int,
        maxBandwidth: Int,
        complexity: Int,
        rxEnabled: Bool,
        txAudioEnabled: Bool
    ) {
        self.compression = compression
        self.bitrate = bitrate
        self.bufferSize = bufferSize
        self.bandwidth = bandwidth
        self.maxBandwidth = maxBandwidth
        self.complexity = complexity
        self.rxEnabled = rxEnabled
        self.txAudioEnabled = txAudioEnabled
    }
}

public struct CommandEncoder: Sendable {
    public init() {}

    public func wrap(body: String, sequence: Int, debug: Bool = false) -> String {
        "C\(debug ? "D" : "")\(sequence)|\(body)"
    }

    public func name(_ value: String) -> String { command("name", value) }
    public func clientGUI(_ value: String?) -> String { command("client gui", value).trimmingCharacters(in: .whitespaces) }
    public func clientStation(_ value: String) -> String { command("client station", value.replacingOccurrences(of: " ", with: "_")) }
    public func clientStartPersistence() -> String { "client start_persistence 1" }
    public func clientUDPPort(_ port: UInt16) -> String { "client udpport \(port)" }
    public func ping() -> String { "ping" }
    public func subscribe(_ topic: SubscriptionTopic) -> String { topic.commandLine }

    public func sliceCreate(frequencyMHz: Double, mode: RadioMode, antenna: String = "ANT1") -> String {
        "slice create freq=\(formatMHz(frequencyMHz)) ant=\(antenna) mode=\(mode.rawValue)"
    }

    public func sliceSet(id: Int, updates: [String: String]) -> String {
        let assignments = updates.keys.sorted().compactMap { key in
            updates[key].map { "\(key)=\($0)" }
        }.joined(separator: " ")
        return "slice s \(id) \(assignments)".trimmingCharacters(in: .whitespaces)
    }

    public func sliceTune(id: Int, frequencyMHz: Double) -> String {
        "slice t \(id) \(formatMHz(frequencyMHz))"
    }

    public func sliceList() -> String { "slice list" }

    public func filter(id: Int, lowHz: Int, highHz: Int) -> String {
        "filt \(id) \(lowHz) \(highHz)"
    }

    public func remoteAudioCommands(profile: RemoteAudioProfile) -> [String] {
        var commands = ["stream create type=remote_audio_rx compression=\(profile.compression.rawValue)"]
        if profile.txAudioEnabled {
            commands.append("stream create type=remote_audio_tx")
        }
        return commands
    }

    public func audioClientAdd(clientID: String, sliceID: Int) -> String {
        "audio client \(clientID) slice \(sliceID) add"
    }

    public func audioClientGain(clientID: String, sliceID: Int, gain: Double) -> String {
        "audio client \(clientID) slice \(sliceID) gain \(String(format: "%.2f", gain))"
    }

    public func audioClientMute(clientID: String, sliceID: Int, muted: Bool) -> String {
        "audio client \(clientID) slice \(sliceID) mute \(muted ? 1 : 0)"
    }

    public func micInput(_ source: String = "pc") -> String { "mic input \(source)" }
    public func xmit(_ enabled: Bool) -> String { "xmit \(enabled ? 1 : 0)" }
    public func transmitSet(_ updates: [String: String]) -> String {
        let body = updates.keys.sorted().compactMap { key in
            updates[key].map { "\(key)=\($0)" }
        }.joined(separator: " ")
        return "transmit set \(body)".trimmingCharacters(in: .whitespaces)
    }

    public func cwWPM(_ value: Int) -> String { "cw wpm \(value)" }
    public func cwIambic(_ enabled: Bool) -> String { "cw iambic \(enabled ? "on" : "off")" }
    public func cwPitch(_ value: Int) -> String { "cw pitch \(value)" }
    public func cwxSend(_ text: String, block: Int) -> String { "cwx send \(escapeText(text)) \(block)" }
    public func cwxInsert(index: Int, text: String, block: Int) -> String { "cwx insert \(index) \(escapeText(text)) \(block)" }
    public func cwxClear() -> String { "cwx clear" }
    public func cwxErase(characters: Int, index: Int? = nil) -> String {
        if let index {
            return "cwx erase \(characters) \(index)"
        }
        return "cwx erase \(characters)"
    }
    public func cwxDelay(_ milliseconds: Int) -> String { "cwx delay \(milliseconds)" }
    public func cwxMacroSave(slot: Int, text: String) -> String { "cwx macro save \(slot) \(escapeText(text))" }
    public func cwxMacroSend(slot: Int, block: Int? = nil) -> String {
        if let block {
            return "cwx macro send \(slot) \(block)"
        }
        return "cwx macro send \(slot)"
    }
    public func cwxQSKEnabled(_ enabled: Bool) -> String { "cwx qsk_enabled \(enabled ? 1 : 0)" }

    private func command(_ name: String, _ value: String?) -> String {
        [name, value].compactMap { $0 }.joined(separator: " ")
    }

    private func formatMHz(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private func escapeText(_ value: String) -> String {
        let encodedSpaces = value.replacingOccurrences(of: " ", with: "\u{7F}")
        return "\"\(encodedSpaces.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

public actor CommandSequenceGenerator {
    private var nextValue = 1

    public init() {}

    public func next() -> Int {
        defer { nextValue += 1 }
        return nextValue
    }
}
