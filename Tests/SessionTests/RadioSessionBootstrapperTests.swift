import Core
import Foundation
import Testing

@Test
func bootstrapPlanContainsExpectedCommandOrder() async {
    let bootstrapper = RadioSessionBootstrapper()
    let profile = ConnectionProfile(name: "Test", mode: .manualHost, host: "127.0.0.1")
    let commands = await bootstrapper.bootstrapPlan(profile: profile, wanProfile: WANOperatingProfile.wanCWNarrow)

    #expect(commands.prefix(3).map(\.body) == ["name FlexLite", "client gui", "client station \(profile.stationName.replacingOccurrences(of: " ", with: "_"))"])
    #expect(commands.map(\.body).contains("sub slice all"))
    #expect(!commands.map(\.body).contains("sub interlock all"))
    #expect(!commands.map(\.body).contains("client start_persistence 1"))
    #expect(!commands.map(\.body).contains(where: { $0.hasPrefix("slice create ") }))
    #expect(commands.map(\.body).contains("stream create type=remote_audio_rx compression=none"))
}

@Test
func persistedOperatorStateRoundTrips() async {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = AppPreferencesStore(defaults: defaults)
    let state = PersistedOperatorState(
        connectionProfile: ConnectionProfile(name: "Persisted", mode: .manualHost, host: "10.0.0.5"),
        wanProfile: WANOperatingProfile.wanSSB,
        audio: AudioPreferenceState(inputDeviceID: "mic-1", outputDeviceID: "spk-1", sidetoneEnabled: true, sidetonePitchHz: 650),
        midi: MidiBindingPreference(sourceID: 42),
        cwMacros: []
    )

    await store.save(state)
    let loaded = await store.load(defaultState: PersistedOperatorState(connectionProfile: ConnectionProfile(name: "Fallback", mode: .manualHost, host: "127.0.0.1"), wanProfile: WANOperatingProfile.wanCWNarrow))

    #expect(loaded.connectionProfile.host == "10.0.0.5")
    #expect(loaded.audio.outputDeviceID == "spk-1")
    #expect(loaded.midi.sourceID == 42)
}
