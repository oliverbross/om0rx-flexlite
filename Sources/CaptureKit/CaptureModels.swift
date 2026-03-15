import Foundation

public enum CaptureDirection: String, Codable, Sendable {
    case inbound
    case outbound
}

public enum ControlClassification: String, Codable, Sendable {
    case command = "C"
    case response = "R"
    case status = "S"
    case message = "M"
    case version = "V"
    case handle = "H"
    case unknown = "?"
}

public struct CaptureBundleManifest: Codable, Sendable {
    public var appVersion: String
    public var osVersion: String
    public var connectionMode: String
    public var radioIdentity: String?
    public var sliceInfo: String?
    public var selectedMode: String?
    public var filterDescription: String?
    public var rxAudioEnabled: Bool
    public var txAudioEnabled: Bool
    public var cwxUsed: Bool
    public var ctr2Attached: Bool

    public init(
        appVersion: String,
        osVersion: String,
        connectionMode: String,
        radioIdentity: String? = nil,
        sliceInfo: String? = nil,
        selectedMode: String? = nil,
        filterDescription: String? = nil,
        rxAudioEnabled: Bool,
        txAudioEnabled: Bool,
        cwxUsed: Bool,
        ctr2Attached: Bool
    ) {
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.connectionMode = connectionMode
        self.radioIdentity = radioIdentity
        self.sliceInfo = sliceInfo
        self.selectedMode = selectedMode
        self.filterDescription = filterDescription
        self.rxAudioEnabled = rxAudioEnabled
        self.txAudioEnabled = txAudioEnabled
        self.cwxUsed = cwxUsed
        self.ctr2Attached = ctr2Attached
    }
}

public struct CaptureSessionMetadata: Codable, Sendable {
    public var sessionName: String
    public var host: String
    public var tcpPort: UInt16
    public var udpPort: UInt16
    public var startedAt: Date
    public var notes: String

    public init(sessionName: String, host: String, tcpPort: UInt16, udpPort: UInt16, startedAt: Date = .now, notes: String = "") {
        self.sessionName = sessionName
        self.host = host
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.startedAt = startedAt
        self.notes = notes
    }
}

public struct OperatorSettingsSnapshot: Codable, Sendable {
    public var values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }
}

public struct ControlLogEntry: Codable, Sendable {
    public var timestamp: Date
    public var direction: CaptureDirection
    public var rawLine: String
    public var classification: ControlClassification

    public init(timestamp: Date = .now, direction: CaptureDirection, rawLine: String, classification: ControlClassification) {
        self.timestamp = timestamp
        self.direction = direction
        self.rawLine = rawLine
        self.classification = classification
    }
}

public struct UDPLogEntry: Codable, Sendable {
    public var timestamp: Date
    public var length: Int
    public var offset: Int
    public var source: String?
    public var destination: String?
    public var streamID: String?
    public var sequence: Int?
    public var summary: String

    public init(
        timestamp: Date = .now,
        length: Int,
        offset: Int,
        source: String? = nil,
        destination: String? = nil,
        streamID: String? = nil,
        sequence: Int? = nil,
        summary: String
    ) {
        self.timestamp = timestamp
        self.length = length
        self.offset = offset
        self.source = source
        self.destination = destination
        self.streamID = streamID
        self.sequence = sequence
        self.summary = summary
    }
}

public struct CaptureBundle: Sendable {
    public var rootURL: URL
    public var manifest: CaptureBundleManifest
    public var sessionMetadata: CaptureSessionMetadata
    public var operatorSettings: OperatorSettingsSnapshot
    public var controlEntries: [ControlLogEntry]
    public var udpEntries: [UDPLogEntry]
    public var udpFrames: Data
}

public enum ReplaySpeed: String, Sendable {
    case realtime
    case half
    case burst
    case step
}

public enum AudioExportAssumption: String, Sendable {
    case pcm16Mono24k
}
