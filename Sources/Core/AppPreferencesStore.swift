import Audio
import CW
import Foundation

public struct MidiBindingPreference: Codable, Hashable, Sendable {
    public var sourceID: Int32?

    public init(sourceID: Int32? = nil) {
        self.sourceID = sourceID
    }
}

public struct AudioPreferenceState: Codable, Hashable, Sendable {
    public var inputDeviceID: String?
    public var outputDeviceID: String?
    public var sidetoneEnabled: Bool
    public var sidetonePitchHz: Int

    public init(
        inputDeviceID: String? = nil,
        outputDeviceID: String? = nil,
        sidetoneEnabled: Bool = true,
        sidetonePitchHz: Int = 600
    ) {
        self.inputDeviceID = inputDeviceID
        self.outputDeviceID = outputDeviceID
        self.sidetoneEnabled = sidetoneEnabled
        self.sidetonePitchHz = sidetonePitchHz
    }
}

public struct PersistedOperatorState: Codable, Sendable {
    public var connectionProfile: ConnectionProfile
    public var wanProfile: WANOperatingProfile
    public var audio: AudioPreferenceState
    public var midi: MidiBindingPreference
    public var cwMacros: [CWMacro]

    public init(
        connectionProfile: ConnectionProfile,
        wanProfile: WANOperatingProfile,
        audio: AudioPreferenceState = AudioPreferenceState(),
        midi: MidiBindingPreference = MidiBindingPreference(),
        cwMacros: [CWMacro] = []
    ) {
        self.connectionProfile = connectionProfile
        self.wanProfile = wanProfile
        self.audio = audio
        self.midi = midi
        self.cwMacros = cwMacros
    }
}

public actor AppPreferencesStore {
    private let defaults: UserDefaults
    private let key = "FlexLite.persistedOperatorState"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(defaultState: PersistedOperatorState) -> PersistedOperatorState {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(PersistedOperatorState.self, from: data) else {
            return defaultState
        }
        return decoded
    }

    public func save(_ state: PersistedOperatorState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
