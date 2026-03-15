# FlexLite

FlexLite is a native macOS Swift package for lightweight remote FlexRadio operation. The repository now contains a protocol-correct SmartSDR TCP command path, persisted direct-connect settings, a session phase model, CWX queue integration, device enumeration, and native transport/audio plumbing for the remaining RX/TX work.

## What The Repo Currently Delivers

- Manual host, LAN, and VPN-first connector architecture.
- SmartSDR command framing in documented `C<seq>|...` form.
- Response and status parsing for version, handle, responses, notices, slice updates, interlock state, and audio stream state.
- Explicit client session phases:
  `disconnected`, `connecting`, `bootstrapping`, `ready`, `rxOnly`, `txArming`, `transmitting`, `recovering`, `error`.
- Persisted connection, WAN profile, audio device, MIDI source, and CW macro preferences.
- One-slice operator UI with direct frequency entry, step tuning, mode changes, filter control, AF gain, mute, and MOX/PTT.
- CWX queueing with block identifiers, clear behavior, stored macros, and radio-side macro save/send commands.
- Device discovery for macOS input devices, CoreAudio output devices, and CoreMIDI sources.
- Native transport/audio primitives for UDP datagram receive, PCM playback, mic capture, and local sidetone.

## Important Truth

This repository is further along than the original scaffold, but it is not truthfully a fully radio-validated v1 yet.

What is still pending hardware or packet-capture validation:

- Real Flex remote RX audio decode and playout against known-good captures.
- Real Flex TX mic audio framing and successful on-air verification.
- Full CTR2 live tuning/PTT validation.
- Temporary disconnect recovery against a real radio session.

Those remaining gaps are documented in:

- [V1-Gap-Report.md](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Docs/V1-Gap-Report.md)
- [Known-Issues.md](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Docs/Known-Issues.md)
- [Manual-Smoke-Test.md](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Docs/Manual-Smoke-Test.md)
- [Completion-Report.md](/Users/oliver/Documents/Projects/OM0RX%20Flex%20Client/Docs/Completion-Report.md)

## Build

```bash
swift build
swift test
open Package.swift
```

## Repo Layout

- `Sources/FlexLiteApp`: SwiftUI operator shell
- `Sources/Core`: session controller, bootstrap planning, persistence, profiles
- `Sources/Transport`: TCP and UDP transport
- `Sources/SmartSDRProtocol`: command encoding and message parsing
- `Sources/Vita49`: VITA framing
- `Sources/Audio`: device enumeration, jitter buffer, playback/capture primitives, sidetone
- `Sources/CW`: CW queue and macro management
- `Sources/MIDI`: MIDI source discovery and mapping primitives
- `Sources/Diagnostics`: structured logging
- `Docs`: architecture, gap report, decision log, test matrix, smoke tests, known issues, completion report

## Recommended Next Validation Step

Use a local LAN-connected FlexRadio session to capture:

1. direct bootstrap traffic
2. RX remote audio stream packets
3. TX microphone stream packets
4. CWX send and clear behavior

Then wire those captures into `Fixtures/` and extend the current session/audio tests before claiming full v1 completion.
