# Diagnostics Guide

FlexLite now exposes the following truth indicators in the app:

- session phase
- current connection status text
- client ID
- audio stream ID if known
- UDP packet count
- sequence-gap count
- jitter buffer depth
- underrun count
- last decode error
- last transport error
- selected audio and MIDI devices
- capture bundle path while capture mode is active

## How To Read Failures

- `No UDP packets`: control path is up, stream path is not reaching the client.
- `UDP packets rising, decode errors rising`: VITA or payload assumption mismatch.
- `No sequence gaps but no audio`: playback path or decoder path is broken.
- `TX blocked by interlock`: radio state or transmit ownership issue.
- `No MIDI sources`: controller not visible to CoreMIDI.
- `Capture path shown but bundle empty`: session ended before any traffic was recorded.
