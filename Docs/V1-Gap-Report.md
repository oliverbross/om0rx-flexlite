# V1 Gap Report

Date: 2026-03-14

This audit compares the current repository to the v1 completion brief and the public FlexRadio SmartSDR API wiki.

## Summary

The repository is a strong scaffold, not a finished v1 operator client.

Current status by subsystem:

- Direct TCP connection: partial
- Session bootstrap: partial
- Reconnect and teardown: weak
- Command framing and response correlation: incomplete
- Single-slice control: partial
- RX audio: scaffold only
- TX mic audio: scaffold only
- CWX and keyboard CW: partial
- MIDI / CTR2: partial
- Settings persistence: missing
- Diagnostics: partial
- Manual smoke validation: missing
This report predated the hardware-truth tooling pass. The repo now includes first-party capture, inspect, replay, and WAV export tooling, but RX/TX/CTR2 still remain unverified against a real radio session.

## Concrete Findings

### [Package.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Package.swift)

- Real: multi-target package layout is in place.
- Real: test targets exist and build.
- Gap: no external codec dependency or system-level decoder integration is wired for remote audio.
- Gap: package structure alone does not prove any radio-facing subsystem works end-to-end.

### [Sources/Transport/TCPCommandClient.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/Transport/TCPCommandClient.swift)

- Real: TCP connect, send, line receive, and disconnect exist.
- Gap: no explicit command sequencing or response matcher at this layer.
- Gap: no reconnect strategy or connection-lost callback.
- Gap: transport state is not surfaced in a way that enforces valid session transitions.

### [Sources/Transport/UDPStreamSocket.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/Transport/UDPStreamSocket.swift)

- Real: UDP send scaffolding exists.
- Gap: no bound receive socket for radio UDP/VITA streams.
- Gap: no packet receive loop, no late/out-of-order handling at the socket boundary.
- Gap: no stream reset or rebind path after reconnect.

### [Sources/SmartSDRProtocol/CommandEncoder.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/SmartSDRProtocol/CommandEncoder.swift)

- Real: bootstrap command names are present.
- Gap: commands are not emitted in the required `C<seq>|...` TCP format from the SmartSDR API.
- Gap: several commands use simplified forms instead of the documented forms most appropriate for v1, including `filt`, `slice t`, and full CWX variants.
- Gap: spaces in CWX payloads are not converted to the radio-side `0x7f` convention described in the official CWX docs.

### [Sources/SmartSDRProtocol/ResponseParser.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/SmartSDRProtocol/ResponseParser.swift)

- Real: version, handle, response, and status prefixes are recognized.
- Gap: status parsing ignores the documented `S<handle>|...` structure.
- Gap: response parsing assumes integer status codes instead of hexadecimal command results.
- Gap: message parsing does not keep message number/severity.

### [Sources/Core/RadioSessionBootstrapper.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/Core/RadioSessionBootstrapper.swift)

- Real: required bootstrap steps are represented.
- Gap: no response-aware bootstrap. Returned client IDs and stream identifiers are not captured.
- Gap: audio client attachment commands are missing.
- Gap: bootstrap always creates a slice instead of reconciling existing slice state first.
- Gap: no failure recovery if mid-bootstrap commands fail.

### [Sources/Core/RadioSessionController.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/Core/RadioSessionController.swift)

- Real: one-slice UI state exists and can emit commands.
- Real: status messages can update basic slice and TX UI state.
- Gap: no explicit state machine for disconnected, connecting, bootstrapping, ready, transmitting, recovering, or error.
- Gap: no persisted preferences for host, ports, WAN profile, audio devices, or MIDI selections.
- Gap: no reconnect timer or backoff after disconnect.
- Gap: no real audio lifecycle management.
- Gap: no radio-side CWX queue tracking.
- Gap: no validation between local UI state and radio response state.

### [Sources/Audio/RemoteAudioPipeline.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/Audio/RemoteAudioPipeline.swift)

- Real: bounded jitter buffer and packet-loss estimate exist.
- Gap: no decoder stage.
- Gap: no actual playback stage.
- Gap: no stream identifier filtering.
- Gap: no packet timestamp use for playout timing.

### [Sources/Audio/AudioDevices.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/Audio/AudioDevices.swift)

- Real: input enumeration exists through AVFoundation.
- Gap: output enumeration is a placeholder and does not reflect actual devices.
- Gap: selected device is not persisted or applied to any engine.

### [Sources/Audio/SidetoneGenerator.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/Audio/SidetoneGenerator.swift)

- Real: local tone generator exists.
- Gap: not integrated into CW queue state or transmit workflow.

### [Sources/CW/CWEngine.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/CW/CWEngine.swift)

- Real: macro store and local queue exist.
- Gap: no block ID tracking for the documented CWX command/response flow.
- Gap: no clear/abort/erase behavior mapped to radio commands.
- Gap: no persistence for macro edits.

### [Sources/MIDI/MidiManager.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/MIDI/MidiManager.swift)

- Real: source enumeration exists.
- Gap: no active CoreMIDI input client/port receiving live events.
- Gap: no persistent mapping preferences.
- Gap: no CTR2 runtime tuning/PTT integration.

### [Sources/FlexLiteApp/MainWindow.swift](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Sources/FlexLiteApp/MainWindow.swift)

- Real: simple operator UI exists.
- Gap: no direct frequency entry field.
- Gap: no visible session phase, stream health, selected devices, CW queue state, or reconnect state.
- Gap: no diagnostics controls or manual recovery controls.

### [README.md](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/README.md)

- Real: repository purpose and bootstrap scope are documented.
- Gap: README still truthfully describes the repo as a scaffold rather than a working v1.
- Gap: no operator instructions, no manual smoke-test steps, no known issues summary.

## External Validation Gaps

- No packet captures are present beyond placeholders.
- No manual smoke-test records are present.
- No on-radio validation has been recorded for RX audio, TX audio, CWX queueing, or CTR2 tuning.

## Audit Conclusion

The next highest-value work is:

1. Fix command and response framing to match the documented SmartSDR TCP protocol.
2. Add a strict session phase model with reconnect-safe teardown.
3. Persist operator settings and selected devices.
4. Implement a real UDP receive path and connect it to an audio playback engine.
5. Promote CWX and MIDI from local-only scaffolding to radio-integrated workflows.
