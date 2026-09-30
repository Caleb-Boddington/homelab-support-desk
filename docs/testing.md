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

## Not yet tested

- A disk actually failing. `smartd-ntfy.sh` has only been read, not triggered.
- The media disk brake at 97%.
- Claude timing out or being logged out, in real conditions. The fallback message path
  exists in `support-triage` but hasn't been exercised deliberately.
