# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| main | Yes |
| Anything else | No |

## What the desk can reach

Claude runs with one allowed tool, `Bash(support-ask:*)`. `support-ask` is a two-line wrapper
that runs `ssh -F /etc/support-desk/ssh_config -- support "$@"`, so Claude cannot add ssh options
of its own (0.1.0 allowed `ssh support` directly, which let `-o ProxyCommand=` run a command
locally; fixed 28/09/2026). The `support` key is pinned on the
host with `command="/usr/local/sbin/support-gate",restrict`, so the host runs the gate whatever
the key asks for, and `restrict` turns off port, agent and X11 forwarding and the terminal.

The gate splits the request on spaces, matches the first word against a fixed menu, and checks
every argument: container and VM IDs must be three digits and must exist, and app and service
names must match `^[A-Za-z0-9][A-Za-z0-9_.@-]{0,63}$`. Anything else is refused and logged.

Tested 23/09/2026 against the live gate: `pct destroy` refused; `facts; touch <file>` refused,
and the file was never created; restarting the desk's own container refused; a bad app name
refused; asking for a shell refused. Rerun on 24/09/2026: `pct destroy 999` returns
`REFUSED: not on the menu: pct (run help)` with exit code 2.

Rerun on 28/09/2026 after a review: `support-ask -o ProxyCommand=... help` and `-o LocalCommand=...`
both refused as "not on the menu: -o", with no file created; headless Claude with the new rule
was denied `ssh support -o ConnectTimeout=5 guests` by Claude Code's permission check. All three
restart verbs now refuse the desk's own container, and `restart-service` only accepts
`*.service` units, so `poweroff.target` is refused.

## What it can still do

Restart any container except the desk's own, and any app or service inside one of the others. That is the
point of it, and it's also the risk: a wrong diagnosis can restart something at a bad moment.

## What leaves your network

The fault, and whatever logs Claude reads while investigating, go to Anthropic as part of the
prompt. Notifications go to ntfy.sh. Anyone who knows your ntfy topic can read them, so use a
long random one.

## Reporting

Open an issue at https://github.com/Caleb-Boddington/homelab-support-desk/issues. This is a
personal project with no support commitment and no response-time promise.
