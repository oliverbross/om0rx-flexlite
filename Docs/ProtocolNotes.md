# Protocol Notes

## Known direct-control facts

- TCP control port: `4992`
- Discovery UDP port: `4991`
- Discovery and media use UDP with VITA-49 framing
- Control is line oriented and mixes responses, status pushes, and informational lines

## Bootstrap commands currently modeled

- `name`
- `client gui`
- `client station`
- `client start_persistence`
- `client udpport`
- `ping`
- `sub radio all`
- `sub slice all`
- `sub tx all`
- `sub cwx all`
- `sub audio_stream all`
- `slice create`
- `slice set`
- `stream create type=remote_audio_rx compression=opus`
- `stream create type=remote_audio_tx`
- `remote_audio bitrate`
- `remote_audio bufsize`
- `remote_audio bw`
- `remote_audio max_bw`
- `remote_audio compl`
- `remote_audio rx_on`
- `remote_audio tx_audio`
- `mic input`
- `xmit`
- `cwx send`
- `cwx clear`
- `cwx insert`
- `cwx delay`

## Important boundaries

- TX audio packet format is intentionally abstracted until validated from captures.
- Audio client identifiers and lifecycle details vary in public examples; these remain isolated from UI code.
- SmartLink is scaffolded as a connector concern, not mixed into direct TCP or UDP logic.
