# Replay Workflow

Once Oliver has a capture bundle, the repo can inspect and replay it immediately.

## Inspect

```bash
swift run flexlite-inspect --capture ./CaptureBundles/<bundle-name>
```

## Replay

Burst replay:

```bash
swift run flexlite-replay --capture ./CaptureBundles/<bundle-name> --mode burst
```

Real-time replay:

```bash
swift run flexlite-replay --capture ./CaptureBundles/<bundle-name> --mode realtime
```

Step replay:

```bash
swift run flexlite-replay --capture ./CaptureBundles/<bundle-name> --mode step
```

## Export Candidate RX Audio

```bash
swift run flexlite-audio-export --capture ./CaptureBundles/<bundle-name> --out ./rx.wav
```

If the first stream in the bundle is not the RX stream, inspect first and rerun with:

```bash
swift run flexlite-audio-export --capture ./CaptureBundles/<bundle-name> --stream 0x84000002 --out ./rx.wav
```
