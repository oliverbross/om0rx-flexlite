# CTR2 Mapping

FlexLite treats CTR2 as a MIDI controller in v1.

## Default bindings

- Relative encoder on CC `16`: tuning delta
- CC `17`: AF gain
- Note `36`: PTT
- Note `37`: CW macro 1
- Note `38`: CW macro 2
- Note `39`: CW macro 3
- CC `18`: filter preset step
- CC `19`: mode step

## Engineering notes

- USB MIDI is the primary path.
- BLE MIDI is planned but secondary.
- Rapid encoder deltas are coalesced before commands are sent to the radio.
- Button inputs are debounced at the mapping layer.
