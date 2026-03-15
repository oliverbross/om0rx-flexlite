# Test Matrix

Date: 2026-03-14

## Automated

| Area | Coverage | Current Status |
|---|---|---|
| Command parsing | Version, handle, status parsing | Covered |
| Command encoding | Bootstrap and remote audio commands | Covered |
| VITA framing | Packet round-trip encode/decode | Covered |
| Capture bundle writer/loader | Bundle persistence and reload | Covered |
| Capture replay | Burst-mode replay of control and UDP events | Covered |
| WAV export | Synthetic capture to WAV export | Covered |
| Jitter buffer | Capacity behavior | Covered |
| CW queue | Store and dequeue basics | Covered |
| MIDI mapping | CTR2 default mapping lookup | Covered |
| Bootstrap order | Basic command ordering | Covered |
| Preferences persistence | Connection/audio/MIDI round-trip | Covered |

## Missing Automated Coverage

| Area | Gap |
|---|---|
| Session state machine | No transition tests yet |
| Reconnect flow | No tests yet |
| Response correlation | No sequence-matching tests yet |
| Settings persistence | No tests yet |
| Audio playback engine | No tests yet |
| TX capture path | No tests yet |
| CWX block IDs and abort flow | No tests yet |
| Live MIDI event handling | No tests yet |
| Reconnect while capture mode is active | No tests yet |

## Manual Smoke Matrix

| Scenario | Needed for v1 | Status |
|---|---|---|
| Manual host connect | Required | Pending hardware validation |
| Slice state load | Required | Pending hardware validation |
| RX audio playback | Required | Pending hardware validation |
| Output device switch | Required | Pending hardware validation |
| TX mic audio | Required | Pending hardware validation |
| Safe RX↔TX transitions | Required | Pending hardware validation |
| Mode and filter changes | Required | Pending hardware validation |
| UI tuning | Required | Pending hardware validation |
| CTR2 tuning | Required | Pending hardware validation |
| CW macro send | Required | Pending hardware validation |
| Keyboard CW send | Required | Pending hardware validation |
| CW abort/clear | Required | Pending hardware validation |
| Temporary disconnect recovery | Required | Pending hardware validation |
| Preference restore on relaunch | Required | Pending local verification |
