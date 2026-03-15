import MIDI
import Testing

@Test
func mapsCtr2Defaults() {
    let mapper = ControlMapper(mappings: CTR2Preset.default)
    let event = MidiEvent(channel: 0, kind: .noteOn, control: 36, value: 127)

    #expect(mapper.action(for: event) == .ptt)
}
