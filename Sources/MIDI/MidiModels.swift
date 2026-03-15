import Foundation

public enum MidiControlKind: String, Codable, Sendable {
    case noteOn
    case noteOff
    case controlChange
}

public struct MidiEvent: Codable, Hashable, Sendable {
    public var channel: UInt8
    public var kind: MidiControlKind
    public var control: UInt8
    public var value: Int

    public init(channel: UInt8, kind: MidiControlKind, control: UInt8, value: Int) {
        self.channel = channel
        self.kind = kind
        self.control = control
        self.value = value
    }
}

public enum ControlAction: Codable, Hashable, Sendable {
    case tuning(deltaHz: Int)
    case afGain
    case filterPresetStep
    case modeStep
    case ptt
    case macro(index: Int)
}

public struct MidiMapping: Codable, Hashable, Sendable {
    public var eventKind: MidiControlKind
    public var control: UInt8
    public var action: ControlAction

    public init(eventKind: MidiControlKind, control: UInt8, action: ControlAction) {
        self.eventKind = eventKind
        self.control = control
        self.action = action
    }
}

public struct ControlMapper: Sendable {
    public var mappings: [MidiMapping]

    public init(mappings: [MidiMapping]) {
        self.mappings = mappings
    }

    public func action(for event: MidiEvent) -> ControlAction? {
        mappings.first {
            $0.eventKind == event.kind && $0.control == event.control
        }?.action
    }
}

public enum CTR2Preset {
    public static let `default`: [MidiMapping] = [
        MidiMapping(eventKind: .controlChange, control: 16, action: .tuning(deltaHz: 10)),
        MidiMapping(eventKind: .controlChange, control: 17, action: .afGain),
        MidiMapping(eventKind: .controlChange, control: 18, action: .filterPresetStep),
        MidiMapping(eventKind: .controlChange, control: 19, action: .modeStep),
        MidiMapping(eventKind: .noteOn, control: 36, action: .ptt),
        MidiMapping(eventKind: .noteOn, control: 37, action: .macro(index: 0)),
        MidiMapping(eventKind: .noteOn, control: 38, action: .macro(index: 1)),
        MidiMapping(eventKind: .noteOn, control: 39, action: .macro(index: 2))
    ]
}
