# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| `main` | ✔ Supported |
| `v1.0.x` | ✔ Supported |

## Reporting a Vulnerability

Do **not** disclose security vulnerabilities publicly. Report privately through
a **GitHub Security Advisory** on this repository.

Include the affected file, a description, reproduction steps, and a suggested
fix if possible.

## Design notes

- **Never settle on failure.** The payment gate settles only on `status:
  success`; unpaid, forged, expired, replayed, or tampered actions return
  `402`/`409`/`INVALID_PARAMS` and never settle.
- **Keys are never committed.** `PRIVATE_KEY` and RPC endpoints are injected at
  runtime via environment variables; the committed proofs come from real
  faucet-funded runs with throwaway keys.
- **Replay is durable.** Idempotency keys and `txHash` records survive a store
  restart by design.
- **Simulator-only scope.** This profile mirrors the tunnel's middleware
  decision semantics in Python — it is a simulation harness, not a wallet
  service.
