# Testing

Everything here was run against the live server. Times are UK time.

## 23/09/2026, first build

### The gate

Each of these was sent through the support key, and each was refused:

- `pct destroy`, a command that isn't on the menu.
- `facts; touch <file>`, a real menu item with a second command chained on. The file was
  never created, because the gate reads `facts;` as one word and it isn't on the menu.
- `restart-ct` for the desk's own container, which would have cut the desk off mid-run.
- `restart-app` with a bad app name.
- A request for an interactive shell.

### The listener

A POST to the wrong token URL was refused with a 403, and the attempt was logged along with
its source address.

### End to end, twice

Forgejo was stopped on purpose both times.

1. A hand-made event, fed straight to the listener. Claude found the stopped app, restarted
   it and reported back.
2. A real outage, caught by Uptime Kuma, from the desk's log:

```
22:26:44  triage: down Forgejo: connect ECONNREFUSED <forgejo>:3000
22:27:59  triage: claude answered for Forgejo: {"fixed": true, ...
          "what_was_done": "Claude restarted it and it's up and taking visitors again."}
22:31:44  triage: up Forgejo
```

That's 75 seconds from detection to a checked fix and a sent notification. Kuma's own
"up" came five minutes later, and the desk correctly stayed quiet, because Claude had
already said it was fixed.

## What went wrong, and the fix

- **Claude wrote in the first person.** The first test's answer said "Something told it to
  shut down at 21:17, but I couldn't see what." The message comes from the server, not a
  chat, so "I" reads as nonsense on a phone. The prompt now asks for the third person
  ("Claude restarted it"), and the second test's answer shows it working.
- **Times were an hour out.** The desk container was on UTC. It's now set to Europe/London.
  The two sets of timestamps in the log above differ by an hour for the same reason.
- **A fix Kuma never noticed would have blocked that monitor for six hours.** If Claude fixed
  something before Kuma saw it come back, Kuma never sent the "up" that clears the state
  file, so the next real fault on that monitor would have been ignored as "already handled".
  A reported fix is now held for 20 minutes, not six hours.
- **The watcher reported itself as failed on an empty log.** Fixed in the same session.

## 13/10/2026, the 0.1.2 security fixes

### Against stand-ins, before going live

Every fix got a check that runs on a PC with stand-ins for `pct`, `ssh`, `claude` and the ntfy
server, so nothing reaches a real machine. Each check was run against the old code first, and
failed on the bug it was written for. The gate's check, for example, went from 19 passed and 25
failed to 44 passed. The checks aren't in this repo yet, because they're written against the
live project's layout. On the copy published here they gave:

| File | Result |
|---|---|
| `host/support-gate` | 44 passed, 0 failed |
| `host/smartd-ntfy.sh` | 7 passed, 0 failed, once the check looked for `backup.service`, the name used here |
| `desk/support-listener.py` | 13 tests, OK |
| `desk/support-triage` | 8 tests, OK |
| `desk/server-notify` | 8 tests, OK |

### On the live server

- A POST from a LAN address that isn't Kuma was refused and logged as "not in allowed-senders".
  Kuma's own address was found by posting from inside its container with a wrong token, which
  the listener logged with the address it came from.
- Inside the listener's service the other SSH key read 0 bytes, and 452 bytes outside it.
- The first version of that lockdown hid the whole of `/root/.ssh/config`, which a second
  process on my desk needs, and broke it for about a minute. Hiding only the key fixed it.
- After each deploy the listener was active and its log had no new errors.

## Not yet tested

- A disk actually failing. `smartd-ntfy.sh` has only been read, not triggered.
- The media disk brake at 97%.
- Claude timing out or being logged out, in real conditions. The fallback message path
  exists in `support-triage` but hasn't been exercised deliberately.
- The four-an-hour restart cap and the unit deny-list on the live gate. Both have only run
  against stand-ins.
- The 8-minute recheck after an unconfirmed fix, in a real outage.
