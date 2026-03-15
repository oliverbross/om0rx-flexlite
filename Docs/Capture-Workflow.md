# Capture Workflow

Use this when you want to gather a real FlexLite session bundle without Wireshark.

## In-App Capture

1. Launch FlexLite.
2. Enter the radio host, TCP port, and a free local UDP port.
3. Click `Enable Capture Mode`.
4. Click `Connect`.
5. Operate long enough to exercise the target path:
   - RX audio startup
   - mode and filter change
   - tuning
   - TX start/stop if safe
   - CWX send/clear
6. Click `Disconnect`.

Expected output:

- a new bundle under `CaptureBundles/YYYYMMDD-HHMMSS-session-name/`
- `control-log.ndjson`
- `udp-log.ndjson`
- `udp-frames.bin`
- `manifest.json`
- `session-metadata.json`
- `operator-settings.json`
- `notes.txt`

## CLI Inspection

```bash
swift run flexlite-inspect --capture ./CaptureBundles/<bundle-name>
```

This prints:

- control timeline summary
- UDP frame summary
- candidate stream IDs
- sequence-gap counts
- payload-format guesses
