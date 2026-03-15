# Architecture

FlexLite is split into small Swift Package targets so the transport, protocol, and operator logic can be tested without the UI.

## Modules

- `FlexLiteApp`: SwiftUI shell with connection, slice control, CW, and diagnostics panes.
- `Core`: orchestration layer. Owns connection profiles, WAN profiles, bootstrap sequencing, state mutation, and tuning coalescing.
- `Transport`: TCP command transport, discovery parsing, UDP stream socket scaffolding. Nothing here knows radio semantics.
- `SmartSDRProtocol`: string command encoder, line parser, subscription planner, and typed state payload models.
- `Vita49`: low-level packet read and write helpers for UDP streams.
- `Audio`: adaptive jitter buffer, remote-audio operating profile, device enumeration, and local sidetone generator.
- `CW`: macro store and buffered keyboard send queue.
- `MIDI`: generic mapping engine plus CTR2 defaults and CoreMIDI source inspection.
- `Diagnostics`: structured log store with export-safe redaction.

## Design rules

- One active slice in v1.
- Explicit PTT for WAN SSB.
- Local sidetone always available for CW.
- Tune deltas are coalesced before leaving the client.
- Audio and packet parsing do not run on the main thread.
- Uncertain protocol areas remain behind typed seams and documented TODOs.

## Session flow

1. Connect TCP control socket on port `4992`.
2. Register client identity and UDP port.
3. Subscribe only to `radio`, `slice`, `tx`, `cwx`, and `audio_stream`.
4. Create or attach to a single operating slice.
5. Create remote RX and TX audio streams.
6. Apply WAN profile parameters independently from slice filter settings.
7. Hand ownership to the UI and controller mappings.
