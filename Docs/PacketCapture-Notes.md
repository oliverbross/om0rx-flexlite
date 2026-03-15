# Packet Capture Notes

This repository is set up for packet-capture-driven validation.

## Capture workflow

1. Put the official client and radio on the same LAN.
2. Capture a connect, slice create, RX audio start, TX toggle, and CWX send session.
3. Save raw control transcripts under `Fixtures/SampleResponses`.
4. Save UDP packet notes and representative hex dumps under `Fixtures/PacketCaptures`.
5. Add regression tests before implementing ambiguous transport details.

## Required validation targets

- Initial `V...` and `H...` lines on connect
- Command ordering after `client gui` and `client udpport`
- Stream creation identifiers
- RX audio packet sequence and timing behavior
- TX audio packet framing
- SmartLink differences once that connector starts
