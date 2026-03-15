# SmartLink Connector Plan

SmartLink is intentionally separated from the first usable build.

## Phase split

- `Phase 1`: ship direct LAN, manual host, and VPN workflows.
- `Phase 2`: add `SmartLinkConnector` behind the same connection abstraction.

## Rules

- Do not leak SmartLink token handling into the direct connector code.
- Keep secrets in Keychain only.
- Redact tokens and account identifiers from exported logs.
- Validate command and stream behavior locally before layering SmartLink traversal on top.
