# Manual Smoke Test

Date prepared: 2026-03-14

These are the required operator validation steps for a real FlexRadio 8400 session.

## Preconditions

- FlexRadio reachable by manual host/IP over LAN or VPN.
- Audio input and output devices attached to the Mac.
- Optional CTR2 connected by USB MIDI.

## Steps

1. Launch FlexLite from Xcode or `swift run FlexLiteApp`.
2. Enter the radio host, TCP port `4992`, and a free local UDP port.
3. Click `Connect`.
4. If collecting truth data, enable `Capture Mode` first and note the capture path shown in the sidebar.
5. Confirm phase transitions reach `ready`.
6. Confirm the active slice frequency and mode populate from radio status.
7. Enter a frequency manually and verify the radio tunes.
8. Change mode and filter limits and verify the radio reflects the change.
9. Adjust AF gain and mute and verify radio-side audio client commands succeed.
10. Verify the selected audio output device is shown correctly.
11. Confirm the UDP packet counter rises once the radio begins sending stream data.
12. Press `Start TX`, speak into the selected mic, and validate TX state transitions only after TX framing is validated.
13. Return to RX and verify no stuck transmit.
14. Send a CW text string and verify the queue count increases then drains.
15. Send a stored CW macro.
16. Press `Clear` and verify the CWX queue aborts.
17. If CTR2 is attached, verify device enumeration and mapped tuning actions.
18. Simulate a temporary disconnect and verify the app enters `recovering` and retries.
19. Relaunch the app and confirm host, ports, devices, and macros are restored.

## Recording

Record each step as:

- `PASS`
- `FAIL`
- `BLOCKED`

Add the date, radio model, WAN profile, and any observed command or stream errors to the session log export.
