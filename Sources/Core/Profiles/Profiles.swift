import Foundation
import SmartSDRProtocol

public enum ConnectionMode: String, Codable, CaseIterable, Sendable {
    case lan
    case manualHost
    case vpn
    case smartLink
}

public struct ConnectionProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var mode: ConnectionMode
    public var host: String
    public var tcpPort: UInt16
    public var udpPort: UInt16
    public var clientID: String?
    public var stationName: String
    public var defaultMode: RadioMode
    public var defaultFrequencyMHz: Double

    public init(
        id: UUID = UUID(),
        name: String,
        mode: ConnectionMode,
        host: String,
        tcpPort: UInt16 = 4992,
        udpPort: UInt16 = 4994,
        clientID: String? = nil,
        stationName: String = Host.current().localizedName ?? "FlexLite",
        defaultMode: RadioMode = .usb,
        defaultFrequencyMHz: Double = 14.074
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.host = host
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.clientID = clientID
        self.stationName = stationName
        self.defaultMode = defaultMode
        self.defaultFrequencyMHz = defaultFrequencyMHz
    }
}

public struct WANOperatingProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var remoteAudio: RemoteAudioProfile
    public var description: String

    public init(id: UUID = UUID(), name: String, remoteAudio: RemoteAudioProfile, description: String) {
        self.id = id
        self.name = name
        self.remoteAudio = remoteAudio
        self.description = description
    }

    public static let wanSSB = WANOperatingProfile(
        name: "WAN SSB",
        remoteAudio: RemoteAudioProfile(compression: .none, bitrate: 32_000, bufferSize: 480, bandwidth: 3_600, maxBandwidth: 4_200, complexity: 5, rxEnabled: true, txAudioEnabled: false),
        description: "PTT-first voice profile with conservative buffering and monitor audio off."
    )

    public static let wanCWNarrow = WANOperatingProfile(
        name: "WAN CW Narrow",
        remoteAudio: RemoteAudioProfile(compression: .none, bitrate: 16_000, bufferSize: 240, bandwidth: 800, maxBandwidth: 1_000, complexity: 4, rxEnabled: true, txAudioEnabled: false),
        description: "Macro-first CW profile with narrow transport audio and local sidetone."
    )

    public static let wanCWLive = WANOperatingProfile(
        name: "WAN CW Live (Experimental)",
        remoteAudio: RemoteAudioProfile(compression: .none, bitrate: 24_000, bufferSize: 120, bandwidth: 1_200, maxBandwidth: 1_600, complexity: 8, rxEnabled: true, txAudioEnabled: false),
        description: "Lower buffering for experimental live keying. Not the default WAN promise."
    )
}
