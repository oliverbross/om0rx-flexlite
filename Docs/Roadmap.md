# Roadmap

## M0 Bootstrap

- Package layout
- Core docs
- Fixtures
- Unit and session tests

## M1 Direct Connection

- TCP connect and line parsing
- UDP port registration
- Minimal subscriptions
- Reconnect-safe bootstrap

## M2 Operator Control

- One active slice
- Frequency entry and tuning
- Mode and filter controls
- TX state and interlock visibility

## M3 Remote RX Audio

- VITA receive path
- Adaptive jitter buffer
- Opus decode integration
- Output device routing

## M4 TX Audio and PTT

- Local mic capture
- TX stream framing validation
- PTT and safe inhibit logic

## M5 CW

- CWX queue
- Macro storage
- Keyboard send
- Local sidetone

## M6 CTR2 MIDI

- Device inspection
- Mapping engine
- CTR2 presets
- Diagnostics page

## M7 Diagnostics and Hardening

- Packet loss estimates
- Session log export
- Recovery metrics

## M8 SmartLink

- Connector implementation
- Keychain-backed secrets
- Validation against packet captures
