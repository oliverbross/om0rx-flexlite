# Implementation Decision Log

Date: 2026-03-14

## 1. Direct-connect first

Decision:
Focus v1 on manual host, LAN, and VPN modes. SmartLink remains scaffolded.

Reason:
This matches the product brief and removes the highest-complexity unknown from the critical path.

## 2. Adopt documented SmartSDR TCP framing now

Decision:
Emit commands in `C<seq>|...` format and parse `R<seq>|<hex>|...`, `S<handle>|...`, and `M<message>|...` exactly as documented.

Reason:
The current plain-text command approach is not protocol-correct and blocks reliable response matching and diagnostics.

Source:
Official FlexRadio SmartSDR API wiki cloned from `https://github.com/flexradio/smartsdr-api-docs.wiki.git`.

## 3. Prefer `filt` and `slice t` over ad hoc field updates where the API is explicit

Decision:
Use the dedicated `filt` command for filter updates and `slice t` for tuning, while still supporting `slice s` for mode and tx updates.

Reason:
These commands are directly documented for v1-critical controls and are less ambiguous than relying on broad `slice s` mutations for everything.

## 4. Preserve an explicit session state machine

Decision:
Model disconnected, connecting, bootstrapping, ready, rx-only, tx-arming, transmitting, recovering, and error.

Reason:
The brief explicitly requires invalid transitions to be rejected and logged. This is also the minimum sane structure for avoiding stuck-TX and phantom reconnect state.

## 5. Persist operator preferences locally

Decision:
Persist connection profile, WAN profile choice, selected audio devices, MIDI source, and CW macros in `UserDefaults`.

Reason:
The v1 brief requires relaunch with preferences restored. `UserDefaults` is the lowest-friction native solution for non-secret settings.

## 6. Keep audio codec handling isolated

Decision:
Build the UDP/VITA receive path, playback engine, and TX capture pipeline behind codec seams rather than smearing codec assumptions through the app.

Reason:
The command/control protocol is documented. Full remote-audio payload details still need packet-capture validation. Isolating the codec seam keeps the client buildable while captures are added.

## 7. Treat on-air verification as a separate truth source

Decision:
Manual smoke docs will explicitly distinguish repository-verified work from hardware-dependent validation.

Reason:
The machine running this session does not have the target radio or known-good captures attached. Claiming full end-to-end validation would be inaccurate.
