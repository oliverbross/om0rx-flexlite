# Known Issues

Date: 2026-03-14

## Current Known Issues

- RX audio decode is not yet validated against captured Flex remote-audio packets.
- TX microphone audio framing is not yet validated against a real radio session.
- The repo includes native playback and capture primitives, but they are not yet wired to a verified Flex stream format.
- MIDI source enumeration exists, but live CoreMIDI event handling and CTR2 tuning/PTT validation are still pending.
- Output device selection is enumerated and persisted, but end-to-end routing against the playback engine still needs integration and verification.
- Audio stream status parsing is generic because the public status docs do not fully specify the `audio_stream` payload fields.
- Reconnect behavior is implemented at the control-session layer, but it has not yet been tested against an actual mid-session network drop.

## Toolchain Note

- Swift 6.2.4 / Xcode 26.3 triggers a compiler IRGen crash on some SwiftUI enum-tag picker patterns in this repo. The current UI avoids those patterns to keep the package buildable.
