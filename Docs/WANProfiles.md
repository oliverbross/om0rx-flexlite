# WAN Profiles

These profiles tune transport behavior, not radio DSP behavior. Slice filter settings stay independent.

## WAN SSB

- RX bitrate: `32000`
- Buffer size: `480`
- Transport bandwidth: `3600`
- Max bandwidth: `4200`
- Opus complexity: `5`
- TX monitor return: off by default

## WAN CW Narrow

- RX bitrate: `16000`
- Buffer size: `240`
- Transport bandwidth: `800`
- Max bandwidth: `1000`
- Opus complexity: `4`
- CWX and local sidetone first

## WAN CW Live (Experimental)

- RX bitrate: `24000`
- Buffer size: `120`
- Transport bandwidth: `1200`
- Max bandwidth: `1600`
- Opus complexity: `8`
- Intended for testing live keying only, not as the default WAN promise
