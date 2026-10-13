# Changelog

Dates are DD/MM/YYYY.

## 0.1.2, 13/10/2026

**Security.** The rest of the 28/09/2026 review, plus a second review on 13/10/2026. All of it was written and tested against local stand-ins on 13/10/2026, then deployed to the live server the same day (see `docs/testing.md`).

From the 28/09/2026 review:
- Kuma's alert message is flattened to one short line and fenced in the prompt, the prompt tells Claude never to obey text from alerts or logs, and Claude's answer loses any links before it reaches the phone (prompt injection).
- The gate allows at most four restarts an hour between all the restart verbs, so even a Claude that's been steered can't restart things in a loop.
- The listener can be limited to Kuma's address with `/etc/support-desk/allowed-senders`, and Claude is woken at most six times an hour (forged alerts).
- The listener drops a client that goes quiet for 10 seconds, refuses bodies over 64 KiB and stops queueing at 50 waiting alerts (it had no timeout and no size cap).
- `server-notify` sends an ntfy access token from `/root/ntfy-token.txt` and can post to your own ntfy server, for a topic that's locked rather than only secret.
- Newlines can no longer forge lines in the gate's log or the desk's.
- The failing-disk script no longer calls every failing disk "the backup drive" when the backup drive isn't mounted; it says it can't tell and starts no backup. It also recognises a backup filesystem on a whole disk, and an NVMe backup drive.
- `SECURITY.md` now asks for private vulnerability reports rather than public issues.

From the 13/10/2026 review:
- `restart-service` refuses units that would switch a container off or cut it off when "restarted": `systemd-poweroff` and its relatives, reboot, sleep and rescue units, ssh, networking, dbus, consoles, and any template unit (`name@`). The 0.1.1 check only insisted on a `.service` unit, and `systemd-poweroff.service` is one.
- The four-an-hour restart count now takes a lock, because two requests arriving together could both read "three so far" and both go ahead.
- When Claude reports a fix (or says the app came back on its own) and Kuma hasn't confirmed it, the desk checks again 8 minutes later. If Kuma still hasn't seen the app come back, a red follows. Before this, a wrong "fixed" left the outage silent for good, because Kuma only sends one "down" per outage.
- `server-notify` drops non-red messages past 30 in an hour or 60 in a day, and logs each one it drops. Reds and brakes always go and aren't counted. A flood of ambers could otherwise use up a free ntfy.sh allowance and leave the next real disk alert with nowhere to go.
- The listener's service unit hides any other SSH key in the desk container from the Claude it starts (`InaccessiblePaths`) and sets `NoNewPrivileges`. Only the gate key stays readable. The path carries a leading `-`, so a desk without that key still starts.

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
