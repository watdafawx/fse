"""fse remote mods, the Python side: a program outside the game that hears what the game emits and calls into it.

    from fse_remote import Remote
    r = Remote("my-mod")              # the name the game sees: remote.call("fse-remote", "connected", "my-mod")

    @r.on("my-mod/")                  # events whose name starts with this (a mod emits them with
    def need(ev):                     #   remote.call("fse-remote", "emit", "my-mod/need", {...}))
        r.call("my-iface", "do", ev["data"]["x"])

    @r.on_connect                     # at start and each time the game comes back (a restart, a new save)
    def hello():
        r.subscribe("on_research_finished")   # a game event, sent as "game/on_research_finished"

    r.run(watch=True)                 # watch: saving a .py beside this program restarts it (a syntax error is
                                      #   refused, the old one keeps running); the game is never touched

Needs the fse loader with the web plugin and the fse-bridge mod. The token is FSE_WEB_TOKEN, else web-token.txt in
FSE_HOME or beside this file's folder (fse's dist/ or the game's fse/ folder); the port FSE_WEB_URL, else the first of
8790-8799 that answers.

The protocol is plain HTTP + JSON, so any language can do the same:
  GET  /api/events?client=<name>&names=<prefix,...>&since=<next>&wait=<ms>
       -> {"events": [{"seq", "name", "data"}], "next": <since for the next call>, "lost": bool}
  POST /api/game {"interface", "function", "args": [...]}  -> {"ok": true, "result"} | {"ok": false, "error"}
  (Authorization: Bearer <token>)
"""
import json
import os
import subprocess
import sys
import threading
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

__all__ = ["Remote", "GameError"]


class GameError(Exception):
    """the game answered a call with an error (no such interface, a Lua error, ...)"""


def _log(msg):
    print(f"[fse-remote {time.strftime('%H:%M:%S')}] {msg}", flush=True)


def _token():
    if os.environ.get("FSE_WEB_TOKEN"):
        return os.environ["FSE_WEB_TOKEN"]
    places = []
    if os.environ.get("FSE_HOME"):
        places.append(Path(os.environ["FSE_HOME"]))
    places.append(Path(__file__).resolve().parent.parent)  # (<fse home>/py/fse_remote.py)
    for p in places:
        f = p / "web-token.txt"
        if f.exists():
            return f.read_text().strip()
    return None


class Remote:
    def __init__(self, client, url=None, token=None):
        self.client = client
        self._url = url or os.environ.get("FSE_WEB_URL")
        self._token = token
        self._handlers = []  # (prefix, fn)
        self._connect = []

    # ---- talking to the game ----------------------------------------------------------------------------------

    def _request(self, method, path, body=None, timeout=15):
        token = self._token or _token()
        if not token:
            raise ConnectionError("no web-token.txt (is the game running through fse? set FSE_HOME or FSE_WEB_TOKEN)")
        bases = [self._url] if self._url else [f"http://127.0.0.1:{p}" for p in range(8790, 8800)]
        last = None
        for base in bases:
            req = urllib.request.Request(base + path, method=method,
                                         data=json.dumps(body).encode() if body is not None else None,
                                         headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=timeout) as f:
                    self._url = base
                    return json.loads(f.read())
            except urllib.error.HTTPError as e:
                if e.code == 401 and not self._url:
                    last = e
                    continue  # (another fse on that port)
                self._url = base
                return json.loads(e.read() or b"{}")
            except OSError as e:
                last = e
        self._url = None if not os.environ.get("FSE_WEB_URL") else self._url
        self._token = None  # (a restarted game writes a new token)
        raise ConnectionError(f"the game doesn't answer: {last}")

    def call(self, interface, function, *args):
        """remote.call(interface, function, ...) on the game thread; its result (raises GameError)"""
        ans = self._request("POST", "/api/game", {"interface": interface, "function": function, "args": list(args)})
        if not ans.get("ok"):
            raise GameError(ans.get("error"))
        return ans.get("result")

    def subscribe(self, event, on=True):
        """a game event (defines.events name) sent out as "game/<event>" (on=False: no longer)"""
        return self.call("$game", "subscribe" if on else "unsubscribe", event)

    def status(self):
        return self.call("$game", "status")

    # ---- handlers -----------------------------------------------------------------------------------------------

    def on(self, prefix):
        """decorator: fn(event) for events whose name starts with prefix; event = {"seq", "name", "data"}"""
        def deco(fn):
            self._handlers.append((prefix, fn))
            return fn
        return deco

    def on_connect(self, fn):
        """decorator: fn() when the game is reached (at start, and after it was gone)"""
        self._connect.append(fn)
        return fn

    def _safe(self, fn, *args):
        try:
            fn(*args)
        except Exception:
            _log(f"error in {getattr(fn, '__name__', fn)} (handled, still running):\n{traceback.format_exc().rstrip()}")

    def poll(self, since=None, wait_ms=20000):
        """one long-poll: (events, next)"""
        q = {"client": self.client, "wait": wait_ms}
        names = sorted({p for p, _ in self._handlers})
        if names and "" not in names:
            q["names"] = ",".join(names)
        if since is not None:
            q["since"] = since
        ans = self._request("GET", "/api/events?" + urllib.parse.urlencode(q), timeout=wait_ms / 1000 + 10)
        if ans.get("lost"):
            _log("some events were lost (too slow: the game keeps the last 4096)")
        return ans.get("events", []), ans.get("next")

    def run(self, watch=False):
        """serve events until stopped; the game may come and go. watch=True: restart on a saved .py (see top)"""
        if watch and not os.environ.get("FSE_REMOTE_CHILD"):
            return _supervise()
        if os.environ.get("FSE_REMOTE_CHILD"):
            threading.Thread(target=_orphan_guard, daemon=True).start()
        since, up = None, False
        while True:
            try:
                events, nxt = self.poll(since, 20000 if up else 0)
            except ConnectionError as e:
                if up:
                    _log(f"game gone ({e}); waiting for it")
                up = False
                time.sleep(1)
                continue
            if not up:
                up = True
                _log(f"connected as {self.client!r} ({self._url})")
                for fn in self._connect:
                    self._safe(fn)
            since = nxt
            for ev in events:
                for prefix, fn in self._handlers:
                    if ev.get("name", "").startswith(prefix):
                        self._safe(fn, ev)


def _orphan_guard():
    """(a child) the supervisor holds our stdin open: when it ends (stopped, killed), so do we"""
    try:
        sys.stdin.buffer.read()
    except Exception:
        pass
    os._exit(0)


def _supervise():
    """the program again as a child, restarted when a .py beside it is saved and compiles"""
    main = Path(sys.modules["__main__"].__file__).resolve()
    folder = main.parent

    def stamp():
        out = {}
        for f in folder.glob("*.py"):
            try:
                out[f] = f.stat().st_mtime
            except OSError:
                pass
        return out

    def start():
        env = dict(os.environ, FSE_REMOTE_CHILD="1")
        return subprocess.Popen([sys.executable, *sys.argv], env=env, stdin=subprocess.PIPE)

    seen, child, told = stamp(), start(), False
    _log(f"watching {folder} (save a .py to restart; Ctrl+C stops)")
    try:
        while True:
            time.sleep(0.5)
            now = stamp()
            changed = [f for f, m in now.items() if seen.get(f) != m]
            seen = now
            if changed:
                bad = None
                for f in changed:
                    try:
                        compile(f.read_text(encoding="utf-8"), str(f), "exec")
                    except SyntaxError as e:
                        bad = f"{f.name}:{e.lineno}: {e.msg}"
                if bad:
                    _log(f"not restarted, syntax error: {bad}")
                    continue
                _log(f"{', '.join(f.name for f in changed)} changed: restarting")
                child.terminate()
                child.wait()
                child, told = start(), False
            elif child.poll() is not None and not told:
                _log(f"stopped (exit {child.returncode}); save a .py to start again")
                told = True
    except KeyboardInterrupt:
        child.terminate()
