#!/usr/bin/env python3
# CT 111: /usr/local/bin/support-listener.py, run by support-listener.service on port 8787.
#
#
# Receives Uptime Kuma's webhook and hands each event to support-triage in the background, so
# Kuma gets its answer at once. The URL carries a random token (/etc/support-desk/token) so
# nothing else on the network can wake Claude. LAN only: never expose this port.
#
# Hardened after the security review of 28/09/2026:
# - B4: the token is plain text on the LAN, so anyone who sees the URL could post fake alerts.
#   If /etc/support-desk/allowed-senders lists addresses (one per line), only those may post.
#   Without the file every address is accepted, as before, and a warning is logged at start.
# - B5: a client that goes quiet for 10 seconds is dropped, a missing or bad length is refused,
#   and a body over 64 KiB is refused unread, so a stalled or huge request can no longer hold a
#   thread or fill memory. At most 50 events may wait for triage.
# - B7: anything written to the log has its control characters escaped, so a newline in a
#   monitor name or message cannot forge an extra log line.
import hmac
import json
import os
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ETC = "/etc/support-desk"
EVENTS = "/var/lib/support-desk/events"
LOG = "/var/log/support-desk.log"
TRIAGE = ["/usr/local/bin/support-triage"]
PORT = 8787

MAX_BODY = 64 * 1024     # Kuma's webhook body is about 2 KiB
TIMEOUT = 10             # seconds a client may stay silent mid-request
MAX_PENDING = 50         # events waiting for triage before new ones are refused
MAX_NAME, MAX_MSG = 100, 500

TOKEN = None             # set by load_config()
ALLOWED = None           # set of allowed sender addresses, or None for any

CONTROL = re.compile(r"[\x00-\x1f\x7f\x85  ]")


def escape(text):
    """Control characters as visible \\xNN, so one log call is always one log line."""
    return CONTROL.sub(lambda m: f"\\x{ord(m.group()):02x}", str(text))


def flatten(text, limit):
    """Control characters to spaces, whitespace squeezed, cut to `limit` characters."""
    return re.sub(r"\s+", " ", CONTROL.sub(" ", str(text))).strip()[:limit]


def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%F %T')}  listener: {escape(msg)}\n")


def load_config():
    global TOKEN, ALLOWED
    with open(os.path.join(ETC, "token")) as f:
        TOKEN = f.read().strip()
    try:
        with open(os.path.join(ETC, "allowed-senders")) as f:
            lines = f.read().splitlines()
        ALLOWED = {l.split("#")[0].strip() for l in lines} - {""} or None
    except FileNotFoundError:
        ALLOWED = None
    if ALLOWED is None:
        log(f"warning: no {ETC}/allowed-senders, so any address with the token can post")


class Handler(BaseHTTPRequestHandler):
    timeout = TIMEOUT

    def reply(self, code, text):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(text.encode())
        self.close_connection = True

    def do_GET(self):
        self.reply(200, "ok") if self.path == "/health" else self.reply(404, "no")

    def do_POST(self):
        sender = self.client_address[0]
        if ALLOWED is not None and sender not in ALLOWED:
            log(f"refused POST from {sender}: not in allowed-senders")
            return self.reply(403, "no")
        if not hmac.compare_digest(self.path.encode(), f"/kuma/{TOKEN}".encode()):
            log(f"refused POST to {self.path[:20]}... from {sender}")
            return self.reply(403, "no")
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            return self.reply(411, "length required")
        if length < 0 or length > MAX_BODY:
            log(f"refused POST from {sender}: body of {length} bytes")
            return self.reply(413, "too big")
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            if not isinstance(body, dict):
                raise ValueError
        except Exception:  # bad JSON, or the client stalled past the timeout
            return self.reply(400, "bad json")
        hb, mon = body.get("heartbeat") or {}, body.get("monitor") or {}
        if not isinstance(hb, dict) or not isinstance(mon, dict):
            return self.reply(400, "bad json")
        name = flatten(mon.get("name") or "", MAX_NAME)
        if not name or hb.get("status") not in (0, 1) or isinstance(hb.get("status"), bool):
            log(f"non-event from Kuma (probably its test button): {str(body.get('msg'))[:80]}")
            return self.reply(200, "ignored")
        os.makedirs(EVENTS, exist_ok=True)
        if len(os.listdir(EVENTS)) >= MAX_PENDING:
            log(f"refused {name}: {MAX_PENDING} events already waiting for triage")
            return self.reply(429, "busy")
        path = os.path.join(EVENTS, f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}-{time.time_ns() % 10**6}.json")
        with open(path, "w") as f:
            json.dump({"monitor": name, "status": hb["status"],
                       "msg": flatten(hb.get("msg") or "", MAX_MSG)}, f)
        subprocess.Popen(TRIAGE + [path], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log(f"{'UP' if hb['status'] == 1 else 'DOWN'} {name}")
        self.reply(200, "ok")

    def log_message(self, *args):
        pass


class Server(ThreadingHTTPServer):
    daemon_threads = True


if __name__ == "__main__":
    load_config()
    Server(("0.0.0.0", PORT), Handler).serve_forever()
