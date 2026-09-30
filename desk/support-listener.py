#!/usr/bin/env python3
# CT 111: /usr/local/bin/support-listener.py, run by support-listener.service on port 8787.
#
#
# Receives Uptime Kuma's webhook and hands each event to support-triage in the background, so
# Kuma gets its answer at once. The URL carries a random token (/etc/support-desk/token) so
# nothing else on the network can wake Claude. LAN only: never expose this port.
import json
import os
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = open("/etc/support-desk/token").read().strip()
EVENTS = "/var/lib/support-desk/events"
LOG = "/var/log/support-desk.log"


def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%F %T')}  listener: {msg}\n")


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, text):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(text.encode())

    def do_GET(self):
        self.reply(200, "ok") if self.path == "/health" else self.reply(404, "no")

    def do_POST(self):
        if self.path != f"/kuma/{TOKEN}":
            log(f"refused POST to {self.path[:20]}... from {self.client_address[0]}")
            return self.reply(403, "no")
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except Exception:
            return self.reply(400, "bad json")
        hb, mon = body.get("heartbeat") or {}, body.get("monitor") or {}
        if not mon.get("name") or hb.get("status") not in (0, 1):
            log(f"non-event from Kuma (probably its test button): {str(body.get('msg'))[:80]}")
            return self.reply(200, "ignored")
        os.makedirs(EVENTS, exist_ok=True)
        path = os.path.join(EVENTS, f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}-{time.time_ns() % 10**6}.json")
        json.dump({"monitor": mon["name"], "status": hb["status"], "msg": hb.get("msg", "")}, open(path, "w"))
        subprocess.Popen(["/usr/local/bin/support-triage", path], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log(f"{'UP' if hb['status'] == 1 else 'DOWN'} {mon['name']}")
        self.reply(200, "ok")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8787), Handler).serve_forever()
