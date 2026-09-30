# Changelog

Dates are DD/MM/YYYY.

## 0.1.1, 28/09/2026

**Security**
- Claude now reaches the gate through `support-ask`, not `ssh support`. OpenSSH reads options after the host name, so the old allow rule let `ssh support -o ProxyCommand=...` run a command on the desk without the gate seeing it. Found by a review the day the repo went public.
- The gate refuses the desk's own container in every restart verb, not just `restart-ct`, and `restart-service` only accepts `.service` units, so it can't be used to power a container off.

## 0.1.0, 24/09/2026

First public release. Running on one server since 23/09/2026; see `docs/testing.md`.

**Included**
- The gate, the host watcher and the failing-disk brake (`host/`).
- The webhook listener, the triage script and its prompt, and the notification sender (`desk/`).
- Memory and disk pressure warnings in the host watcher, added 25/09/2026 after one container sat at its memory cap all day and nothing else noticed.

**Left out on purpose**
- The deploy script, which names the real server.
- The backup script and heartbeat, which carry personal paths and secret check-in URLs.
- Media-specific fixes and a separate report desk, which are specific to one household and
  would widen the gate's menu well past what this release describes.
