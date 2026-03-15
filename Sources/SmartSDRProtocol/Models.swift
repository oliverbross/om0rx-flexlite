import Foundation

public enum RadioMode: String, Codable, CaseIterable, Sendable {
    case usb = "USB"
    case lsb = "LSB"
    case cw = "CW"
}

public struct Slice: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public var frequencyMHz: Double
    public var mode: RadioMode
    public var filterLowHz: Int
    public var filterHighHz: Int
    public var isTransmitSlice: Bool
    public var isMuted: Bool
    public var afGain: Int

    public init(
        id: Int = 0,
        frequencyMHz: Double = 14.074,
        mode: RadioMode = .usb,
        filterLowHz: Int = 300,
        filterHighHz: Int = 2800,
        isTransmitSlice: Bool = true,
        isMuted: Bool = false,
        afGain: Int = 50
    ) {
        self.id = id
        self.frequencyMHz = frequencyMHz
        self.mode = mode
        self.filterLowHz = filterLowHz
        self.filterHighHz = filterHighHz
        self.isTransmitSlice = isTransmitSlice
        self.isMuted = isMuted
        self.afGain = afGain
    }
}

public enum InterlockState: String, Codable, CaseIterable, Sendable {
    case receive = "RECEIVE"
    case ready = "READY"
    case notReady = "NOT_READY"
    case pttRequested = "PTT_REQUESTED"
    case transmitting = "TRANSMITTING"
    case txFault = "TX_FAULT"
    case timeout = "TIMEOUT"
    case stuckInput = "STUCK_INPUT"
    case unknown = "UNKNOWN"
}

public struct TxState: Codable, Sendable, Equatable {
    public var isTransmitting: Bool
    public var interlock: String
    public var interlockState: InterlockState
    public var reason: String?
    public var txAllowed: Bool

    public init(
        isTransmitting: Bool = false,
        interlock: String = "UNKNOWN",
        interlockState: InterlockState = .unknown,
        reason: String? = nil,
        txAllowed: Bool = false
    ) {
        self.isTransmitting = isTransmitting
        self.interlock = interlock
        self.interlockState = interlockState
        self.reason = reason
        self.txAllowed = txAllowed
    }
}

public struct AudioStreamState: Codable, Sendable, Equatable {
    public var rxEnabled: Bool
    public var txAudioEnabled: Bool
    public var bufferDepth: Int
    public var streamID: String?
    public var compression: String?

    public init(
        rxEnabled: Bool = false,
        txAudioEnabled: Bool = false,
        bufferDepth: Int = 0,
        streamID: String? = nil,
        compression: String? = nil
    ) {
        self.rxEnabled = rxEnabled
        self.txAudioEnabled = txAudioEnabled
        self.bufferDepth = bufferDepth
        self.streamID = streamID
        self.compression = compression
    }
}

public struct NetworkMetrics: Codable, Sendable, Equatable {
    public var commandRTTMilliseconds: Double
    public var audioBufferDepthFrames: Int
    public var packetLossEstimate: Double
    public var underrunCount: Int

    public init(commandRTTMilliseconds: Double = 0, audioBufferDepthFrames: Int = 0, packetLossEstimate: Double = 0, underrunCount: Int = 0) {
        self.commandRTTMilliseconds = commandRTTMilliseconds
        self.audioBufferDepthFrames = audioBufferDepthFrames
        self.packetLossEstimate = packetLossEstimate
        self.underrunCount = underrunCount
    }
}

public enum SubscriptionTopic: String, CaseIterable, Codable, Sendable {
    case radio
    case slice
    case tx
    case cwx
    case audioStream = "audio_stream"

    public var commandLine: String {
        "sub \(rawValue) all"
    }
}

public struct CommandResponse: Sendable, Equatable {
    public let sequence: Int
    public let codeHex: String
    public let code: UInt32
    public let payload: String
    public let debugOutput: String?

    public var isSuccess: Bool {
        code == 0
    }

    public init(sequence: Int, codeHex: String, code: UInt32, payload: String, debugOutput: String?) {
        self.sequence = sequence
        self.codeHex = codeHex
        self.code = code
        self.payload = payload
        self.debugOutput = debugOutput
    }
}

public struct StatusMessage: Sendable, Equatable {
    public let handle: String
    public let object: String
    public let identifier: String?
    public let properties: [String: String]

    public init(handle: String, object: String, identifier: String?, properties: [String: String]) {
        self.handle = handle
        self.object = object
        self.identifier = identifier
        self.properties = properties
    }
}

public enum MessageSeverity: Int, Codable, Sendable {
    case informational = 0
    case warning = 1
    case error = 2
    case fatal = 3
}

public struct RadioNotice: Sendable, Equatable {
    public let codeHex: String
    public let severity: MessageSeverity
    public let text: String

    public init(codeHex: String, severity: MessageSeverity, text: String) {
        self.codeHex = codeHex
        self.severity = severity
        self.text = text
    }
}

public enum RadioMessage: Sendable, Equatable {
    case version(String)
    case handle(String)
    case response(CommandResponse)
    case status(StatusMessage)
    case notice(RadioNotice)
    case unknown(String)
}
