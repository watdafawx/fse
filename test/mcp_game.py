"""MCP server (stdio, no dependencies): a warm headless Factorio that an agent tests mods in.

One headless server (its own write-data folder, test/run/mcp-game) with a mod and optionally one of its test cases,
driven over the game's own RCON. The game is held at speed 0.01 (a server can't pause); time moves through `ticks`.
Tools:

  start(mod, case?, with?, base?, fse?, client?)   map created, server up (~3 s); a running one is replaced.
                         client: a real game window joins it too (test/run/mcp-client), for the GUI tools below
  lua(code, mod?)        code run as a function body in mod's own Lua state (`/sc __mod__`), the return value as text
  reload()               the game saved, the mods copied again from their folders, the save loaded (~3 s, state kept:
                         control.lua and data.lua changes both; game.reload_script does nothing on a server)
  save(name)             a restore point: the game as it is now, kept until the next start
  restore(name?)         back to a restore point (~3 s), the mods copied again like reload; without a name, the list
  ticks(n)               the game runs about n ticks as fast as it can, then is held again; new log errors in the answer
  log(errors?, lines?)   the game's log (or only its error lines)
  output(name?)          a script-output file (helpers.write_file), or the list of them
  stop()
  test(mod, case?, with?)  lua_check.py over the mod, then its test/run.py (--all without a case); only the failures
                         and the totals in the answer. Runs its own games: the warm one is left alone.
With a client (both games through fse/dist's launcher; the client's input goes into its SDL event queue through
FSE's std.inject over its web API, so the desktop's mouse and keys are never touched and the window needs no focus;
the game ignores posted window messages. Pictures via PrintWindow):
  shot(width?)           the client window's picture (an image; full size saved under test/run/mcp-game/shots)
  click(x, y, button?, shot?)   a click at (x, y) in the last shot's pixels; the game runs until the server has
                         applied it (an F12 custom input from the mcp-sync helper mod, injected after it, is the
                         barrier), then a new shot
  key(key, shot?)        a key press: "e", "escape", "control+c"; then like click
  type(text, shot?)      text into the focused text field
  hover(x, y) / wheel(x, y, notches)

Registered in the dev folder's .mcp.json as "factorio". Checks: test/run_mcp_game.py, test/run_mcp_client.py.
"""
import atexit
import base64
import ctypes
import io
import json
import os
import re
import secrets
import shutil
import socket
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from factorio_paths import BASE_MODS, PATHS, _info, run_dir, stage_mods, user_mod, with_deps  # noqa: E402

RUN = HERE / "run" / "mcp-game"
POINTS = RUN / "points"
SHOTS = RUN / "shots"
CLIENT = HERE / "run" / "mcp-client"
# (the client's own config: windowed, quiet, light on the GPU; written under run_dir's [path] section)
CLIENT_INI = """[general]
locale=en
[sound]
master-volume=0
[graphics]
full-screen=false
graphics-quality=low
video-memory-usage=low
"""
LAUNCHER = HERE.parent / "dist" / "fse-launcher.exe"
ERROR = re.compile(r"Error|non-recoverable")
HELD = "/sc game.speed = 0.01"
HELD_TITLE = "Factorio (test game, HELD between Claude's steps: the low FPS/UPS is on purpose, ticks run at full speed)"


class Rcon:
    """the Source RCON protocol Factorio speaks: auth once, then one command, one answer"""

    def __init__(self, port, password):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=60)
        self.id = 0
        self.send(3, password)
        while True:
            rid, kind, _ = self.recv()
            if kind == 2:  # (the auth answer; id -1 when the password is wrong)
                if rid == -1:
                    raise RuntimeError("rcon: wrong password")
                return

    def send(self, kind, body):
        self.id += 1
        data = body.encode("utf-8") + b"\0\0"
        self.sock.sendall(struct.pack("<iii", len(data) + 8, self.id, kind) + data)

    def exact(self, n):
        buf = b""
        while len(buf) < n:
            part = self.sock.recv(n - len(buf))
            if not part:
                raise ConnectionError("rcon: the game closed the connection")
            buf += part
        return buf

    def recv(self):
        (size,) = struct.unpack("<i", self.exact(4))
        rid, kind = struct.unpack("<ii", self.exact(8))
        return rid, kind, self.exact(size - 8)[:-2].decode("utf-8", "replace")

    def command(self, text):
        self.send(2, text)
        return self.recv()[2]


class Game:
    def __init__(self):
        self.proc = self.rcon = None
        self.mods = {}
        self.common = self.env = None
        self.log_seen = 0
        self.client = self.hwnd = None
        self.want_client = self.fse = False
        self.port, self.md, self.scale = None, None, 1.0
        self.web = self.web_token = None

    def log_text(self):
        f = RUN / "factorio-current.log"
        return f.read_text(encoding="utf-8", errors="replace") if f.exists() else ""

    def errors_note(self):
        text = self.log_text()
        new, self.log_seen = text[self.log_seen:], len(text)
        errors = [l for l in new.splitlines() if ERROR.search(l)]
        return ("\nerrors in the log:\n" + "\n".join(errors[-30:])) if errors else ""

    def start(self, mod, case=None, base=None, fse=False, client=False, **kw):
        self.stop()
        if client and gi().game_window(timeout=0):
            raise RuntimeError("a Factorio window is open (yours?): close it first, the client can't run beside it")
        fse = fse or client  # (the client's input goes in through FSE's std.inject; both peers need fse-std)
        self.want_client, self.fse = client, fse
        mod = Path(mod).resolve()
        if not (mod / "info.json").exists():
            raise ValueError(f"{mod} has no info.json")
        # (keyed by info.json name: the folder trash-slot holds wx-trash-slot; `with` mods bring what they require)
        extra = {}
        for n in kw.get("with") or []:
            src = user_mod(n)
            extra[_info(src).get("name") or n] = src
        main = _info(mod).get("name") or mod.name
        self.mods = {main: mod, **with_deps(extra, have=[main])}
        if case:
            self.mods[case] = mod / "test" / case
        if fse:
            self.mods["fse-std"] = HERE.parent / "mods" / "fse-std"
        if client:
            self.mods["mcp-sync"] = sync_mod()
        run = run_dir(RUN)
        md = self.md = run / "mcp-mods"
        stage_mods(md, self.mods, BASE_MODS if base is None else base)
        self.env = {k: v for k, v in os.environ.items() if not (fse and k == "FSE_OFF")}
        self.common = [str(LAUNCHER if fse else PATHS["factorio_exe"]), "--config", str(run / "config.ini"),
                       "--mod-directory", str(md)]
        save = run / "mcp.zip"
        save.unlink(missing_ok=True)
        shutil.rmtree(POINTS, ignore_errors=True)  # (a restore point belongs to the map and mods it was saved with)
        p = subprocess.run(self.common + ["--create", str(save)], capture_output=True, text=True, encoding="utf-8",
                           errors="replace", env=self.env)
        if p.returncode or not save.exists():
            raise RuntimeError("the map wasn't created:\n" + p.stdout[-3000:])
        self.launch(save)
        joined = self.join() if client else ""
        return (f"running {', '.join(self.mods)} at tick {self.lua('return game.tick')}, held" + joined
                + self.errors_note())

    def launch(self, save):
        settings = RUN / "server-settings.json"
        cfg = json.loads((PATHS["game_data"] / "server-settings.example.json").read_text(encoding="utf-8"))
        cfg.update({"name": "mcp-game", "description": "", "visibility": {"public": False, "lan": False},
                    "require_user_verification": False, "autosave_interval": 0, "auto_pause": False,
                    "username": "", "password": "", "token": "", "game_password": ""})
        settings.write_text(json.dumps(cfg))
        password = secrets.token_hex(8)
        with socket.socket() as s:  # (two free ports: RCON's and the game's UDP one)
            s.bind(("127.0.0.1", 0))
            rcon_port = s.getsockname()[1]
        with socket.socket(type=socket.SOCK_DGRAM) as s:
            s.bind(("127.0.0.1", 0))
            game_port = s.getsockname()[1]
        self.port = game_port
        self.log_seen = 0
        # (the last server's log says InGame too: gone first, so the wait below is for this one)
        (RUN / "factorio-current.log").unlink(missing_ok=True)
        self.proc = subprocess.Popen(
            self.common + ["--start-server", str(save), "--server-settings", str(settings), "--port", str(game_port),
                           "--bind", "127.0.0.1", "--rcon-bind", f"127.0.0.1:{rcon_port}", "--rcon-password", password],
            env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            creationflags=subprocess.BELOW_NORMAL_PRIORITY_CLASS)
        end = time.time() + 180
        while "changing state from(CreatingGame) to(InGame)" not in self.log_text():
            if self.proc.poll() is not None or time.time() > end:
                text = self.log_text()
                self.stop()
                raise RuntimeError("the server didn't start:\n" + text[-3000:])
            time.sleep(0.2)
        self.rcon = Rcon(rcon_port, password)
        self.command(HELD)

    def command(self, text):
        if not self.rcon:
            raise RuntimeError("no game running: start first")
        out = self.rcon.command(text).rstrip("\n")
        if text.startswith("/sc game.speed ="):
            self.title(text == HELD)
        return out

    def title(self, held):
        """the client window's title says when the game is held: a client draws no faster than the server ticks,
        so a held game shows 3-5 FPS/UPS, which looks like lag to someone watching"""
        if self.hwnd and ctypes.windll.user32.IsWindow(self.hwnd):
            ctypes.windll.user32.SetWindowTextW(self.hwnd, HELD_TITLE if held else "Factorio (test game, running)")

    def lua(self, code, mod=None):
        wrapped = (f"local ok, r = pcall(function() {code}\nend) "
                   "rcon.print(ok and (type(r) == 'string' and r or serpent.line(r, {comment = false, nocode = true}))"
                   " or ('error: ' .. tostring(r)))")
        return self.command(f"/sc {f'__{mod}__ ' if mod else ''}{wrapped}")

    def server_save(self):
        """the game saved over its own save (RUN/mcp.zip); answers that file"""
        seen = len(self.log_text())
        self.command("/server-save")
        end = time.time() + 60
        while "Saving finished" not in self.log_text()[seen:]:
            if time.time() > end:
                raise RuntimeError("the game didn't save")
            time.sleep(0.1)
        return RUN / "mcp.zip"

    def relaunch(self, save):
        """the server stopped, the mods copied again from their folders, `save` loaded"""
        self.stop()
        md = RUN / "mcp-mods"
        for name, src in self.mods.items():
            if src.is_dir():
                shutil.rmtree(md / name, ignore_errors=True)
                shutil.copytree(src, md / name, ignore=shutil.ignore_patterns("test", ".git", "__pycache__"))
        self.launch(save)
        if self.want_client:
            self.join()

    def join(self):
        """a real game window joins the server as a player (its own write-data, test/run/mcp-client); answers a note"""
        t0 = time.time()
        # (no crash-site cutscene for the player about to be made: at its end the game waits for Tab)
        self.lua('if remote.interfaces.freeplay then remote.call("freeplay", "set_skip_intro", true) '
                 'remote.call("freeplay", "set_disable_crashsite", true) end')
        run_dir(CLIENT)
        ini = CLIENT / "config.ini"
        if "[graphics]" not in ini.read_text(encoding="utf-8"):
            ini.write_text(ini.read_text(encoding="utf-8") + CLIENT_INI, encoding="utf-8")
        log = CLIENT / "factorio-current.log"
        log.unlink(missing_ok=True)
        # (a web token of its own: the client's FSE web port is the one of 18790-18799 that takes it)
        self.web_token = secrets.token_hex(16)
        env = dict(self.env, FSE_WEB_TOKEN=self.web_token, FSE_LOG=str(CLIENT / "fse.log"))
        si = subprocess.STARTUPINFO()
        si.dwFlags, si.wShowWindow = 1, 4  # (STARTF_USESHOWWINDOW, SW_SHOWNOACTIVATE: not in front of the user's work)
        self.client = subprocess.Popen(
            [self.common[0], "--config", str(ini), "--mod-directory", str(self.md), "--mp-connect",
             f"127.0.0.1:{self.port}"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            startupinfo=si)
        self.command("/sc game.speed = 1")  # (a held server would take minutes to let the client catch up)
        try:
            end = time.time() + 240
            while self.lua("return #game.connected_players") in ("0", ""):
                if self.client.poll() is not None or time.time() > end:
                    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
                    raise RuntimeError("the client didn't join:\n" + text[-3000:])
                time.sleep(0.5)
        finally:
            self.command(HELD)
        self.hwnd = gi().game_window(timeout=30)
        if not self.hwnd:
            raise RuntimeError("the client joined but has no window")
        self.title(True)
        self.web = next((p for p in range(18790, 18800) if self.web_get(p, "/api/status")), None)
        if not self.web:
            raise RuntimeError("the client's FSE web API didn't answer (fse/dist built? see test/run/mcp-client/fse.log)")
        return f"; client joined in {time.time() - t0:.0f} s"

    def web_get(self, port, path):
        req = urllib.request.Request(f"http://127.0.0.1:{port}{path}",
                                     headers={"Authorization": f"Bearer {self.web_token}"})
        try:
            with urllib.request.urlopen(req, timeout=2) as r:
                return r.status == 200
        except OSError:
            return False

    def inject(self, what):
        """input into the client's SDL through FSE (std.inject): the game takes it as the real mouse and keyboard"""
        self.window()
        req = urllib.request.Request(f"http://127.0.0.1:{self.web}/api/native/std/inject",
                                     data=json.dumps(what).encode(), method="POST",
                                     headers={"Authorization": f"Bearer {self.web_token}"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                text = r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:  # (502: the plugin's own error, in the body)
            text = e.read().decode("utf-8", "replace")
        if "injected" not in text:
            raise RuntimeError(f"inject {what}: {text}")

    def window(self):
        if not self.client or self.client.poll() is not None:
            raise RuntimeError("no client: start(..., client=true)")
        if not ctypes.windll.user32.IsWindow(self.hwnd):
            self.hwnd = gi().game_window(timeout=5)
        return self.hwnd

    def live(self, secs):
        """the game at normal speed for `secs` (GUI events take a tick), then held"""
        self.command("/sc game.speed = 1")
        time.sleep(secs)
        self.command(HELD)

    def shot(self, width=1280):
        img = gi().picture(self.window())
        if img is None:
            raise RuntimeError("the client window has no size (minimized?)")
        SHOTS.mkdir(parents=True, exist_ok=True)
        n = len(list(SHOTS.glob("*.png"))) + 1
        full = SHOTS / f"{n:03}.png"
        img.save(full)
        small = img
        if width and img.width > width:
            small = img.resize((width, round(img.height * width / img.width)))
        self.scale = img.width / small.width
        buf = io.BytesIO()
        small.save(buf, "JPEG", quality=85)
        note = (f"window {img.width}x{img.height}, shown {small.width}x{small.height} (click in these pixels); "
                f"saved {full}")
        return [{"type": "text", "text": note},
                {"type": "image", "data": base64.b64encode(buf.getvalue()).decode(), "mimeType": "image/jpeg"}]

    def act(self, what, steps, shot):
        """`steps` injected with the game running (a GUI click becomes an action the server applies a few ticks
        later), then ~0.5 s more, held again; a shot back, or `what` and new log errors"""
        self.command("/sc game.speed = 1")
        try:
            for i, step in enumerate(steps):
                if i:
                    time.sleep(0.1)  # (a frame between the move and the press: the game finds what's hovered)
                # (first, the window is told it has the focus: the game drops input while it thinks it hasn't)
                self.inject({"focus": True, **step} if i == 0 else step)
            what += self.barrier()
        finally:
            self.command(HELD)
        return self.shot() if shot else what + self.errors_note()

    def barrier(self):
        """F12 injected after the input, then the game run until the server has seen it: a client's actions are applied
        in order, so what came before it has been applied too (a click takes 0.5-2 s to come back from a held game)"""
        n = lambda: self.lua('return remote.call("mcp-sync", "n")')
        time.sleep(0.15)  # (a tap's release comes 60 ms after its press)
        n0 = n()
        self.inject({"key": "f12"})
        end = time.time() + 15
        while n() == n0:
            if time.time() > end:
                return " (the game never took the sync key: is a text field holding the keyboard?)"
            time.sleep(0.05)
        time.sleep(0.2)  # (the client draws the change)
        return ""

    def at(self, x, y):
        return {"x": round(x * self.scale), "y": round(y * self.scale)}

    def click(self, x, y, button="left", shot=True):
        return self.act(f"clicked {button} at {x}, {y}", [self.at(x, y), {"button": button}], shot)

    def hover(self, x, y, shot=True):
        return self.act(f"mouse at {x}, {y}", [self.at(x, y)], shot)

    def wheel(self, x, y, notches, shot=True):
        return self.act(f"wheel {notches} at {x}, {y}", [self.at(x, y), {"wheel": notches}], shot)

    def key(self, key, shot=True):
        return self.act(f"pressed {key}", [{"key": key}], shot)

    def type(self, text, shot=True):
        return self.act(f"typed {len(text)} characters", [{"text": text}], shot)

    def reload(self):
        tick = self.lua("return game.tick")
        self.relaunch(self.server_save())
        return f"reloaded at tick {tick}, now {self.lua('return game.tick')}, held" + self.errors_note()

    def points(self):
        return sorted(f.stem for f in POINTS.glob("*.zip")) if POINTS.is_dir() else []

    def save(self, name):
        if not re.fullmatch(r"[\w.-]+", name):
            raise ValueError(f"{name!r}: letters, digits, _ . - only")
        tick = self.lua("return game.tick")
        POINTS.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(self.server_save(), POINTS / f"{name}.zip")
        return f"saved {name!r} at tick {tick}; points: {', '.join(self.points())}"

    def restore(self, name=None):
        if not name:
            return "points: " + (", ".join(self.points()) or "(none)")
        point = POINTS / f"{name}.zip"
        if not point.exists():
            raise ValueError(f"no point {name!r}; points: {', '.join(self.points()) or '(none)'}")
        if not self.rcon:
            raise RuntimeError("no game running: start first")
        save = RUN / "mcp.zip"
        self.stop()  # (the server holds its save open)
        shutil.copyfile(point, save)
        self.relaunch(save)
        return f"restored {name!r}, tick {self.lua('return game.tick')}, held" + self.errors_note()

    def ticks(self, n):
        goal = int(self.lua("return game.tick")) + n
        self.command("/sc game.speed = 100")
        while True:
            t = int(self.lua("return game.tick"))
            if t >= goal or self.proc.poll() is not None:
                break
            time.sleep(0.02 if goal - t < 600 else 0.2)
        self.command(HELD)
        return f"tick {t}" + self.errors_note()

    def log(self, errors=False, lines=60):
        text = self.log_text().splitlines()
        if errors:
            text = [l for l in text if ERROR.search(l)]
        return "\n".join(text[-lines:]) or "(nothing)"

    def output(self, name=None):
        out = RUN / "script-output"
        if not name:
            return "\n".join(sorted(str(p.relative_to(out)) for p in out.rglob("*") if p.is_file())) or "(none)"
        return (out / name).read_text(encoding="utf-8", errors="replace")

    def stop(self):
        if self.client and self.client.poll() is None:  # (/T: through the launcher, the game is its child)
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(self.client.pid)], capture_output=True)
            self.client.wait()
        self.client = self.hwnd = None
        if self.rcon:
            self.rcon.sock.close()
        if self.proc and self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()
        self.proc = self.rcon = None
        return "stopped"


def test(mod, case=None, **kw):
    """lua_check over the mod, then its own run.py; the answer keeps the failures and the totals"""
    mod = Path(mod).resolve()
    run_py = mod / "test" / "run.py"
    if not run_py.exists():
        raise ValueError(f"{mod} has no test/run.py")
    lines = []
    p = subprocess.run([sys.executable, str(HERE / "lua_check.py"), str(mod)], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    lua_ok = p.returncode == 0
    lines += [l for l in p.stdout.splitlines() if l.startswith("FAIL") or "Lua files" in l] or [p.stdout + p.stderr]
    args = [case] if case else ["--all"]
    for n in kw.get("with") or []:
        args += ["--with", n]
    p = subprocess.run([sys.executable, str(run_py), *args], cwd=mod, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    out = (p.stdout + p.stderr).strip().splitlines()
    if case:  # (one case prints its whole result: the tail is enough)
        lines += out[-40:] if p.returncode else [f"PASS {case}"]
    else:  # (--all: a line per case, the failing ones followed by their tail; PASS lines are only noise here)
        lines += [l for l in out if not l.startswith("PASS ")]
    return ("PASS" if p.returncode == 0 and lua_ok else "FAIL") + "\n" + "\n".join(lines)


def sync_mod():
    """the client's helper mod (made under test/run/mcp-game): a custom input on F12 counted in storage, read by
    remote.call("mcp-sync", "n"): the barrier the GUI tools wait on"""
    d = RUN / "mcp-sync"
    d.mkdir(parents=True, exist_ok=True)
    (d / "info.json").write_text(json.dumps({"name": "mcp-sync", "version": "0.1.0", "title": "mcp sync",
                                             "author": "fse", "factorio_version": "2.0"}))
    (d / "data.lua").write_text('data:extend{{type = "custom-input", name = "mcp-sync", key_sequence = "F12", '
                                'consuming = "game-only"}}\n')
    (d / "control.lua").write_text('script.on_event("mcp-sync", function() storage.n = (storage.n or 0) + 1 end)\n'
                                   'remote.add_interface("mcp-sync", {n = function() return storage.n or 0 end})\n')
    return d


def gi():
    """gui_input, loaded on first use (it makes the process DPI aware and needs Pillow)"""
    import gui_input
    return gui_input


GAME = Game()
atexit.register(GAME.stop)


def schema(props, required=()):
    return {"type": "object", "properties": props, "required": list(required)}


S, I, B = {"type": "string"}, {"type": "integer"}, {"type": "boolean"}
TOOLS = {
    "start": ("Start a headless Factorio server with a mod folder and optionally one of its test cases "
              "(<mod>/test/<case>, a scenario mod). Replaces a running one. The game is held (speed 0.01) until "
              "`ticks`. Base mods: base, elevated-rails, quality, space-age unless `base` is given (e.g. [\"base\"]). "
              "`with`: more mods by name from the user's own mods folder (newest zip). `fse`: start through FSE's "
              "launcher (fse/dist) with fse-std. `client`: a real game window joins as a player (about 20-40 s more; "
              "refused while the user's own Factorio is open) for shot/click/key/type; reload and restore bring it "
              "back too.",
              schema({"mod": {**S, "description": "absolute path of the mod folder (has info.json)"},
                      "case": S, "with": {"type": "array", "items": S}, "base": {"type": "array", "items": S},
                      "fse": B, "client": B}, ["mod"])),
    "lua": ("Run Lua on the game thread as a function body; `return x` gives x (serpent.line for tables, errors as "
            "'error: ...'). With `mod`, it runs in that mod's own Lua state (its globals and storage; control.lua's "
            "locals are not visible). Without, in the scenario's.",
            schema({"code": S, "mod": S}, ["code"])),
    "reload": ("After editing a mod: save, copy the mods again from their folders, load the save (~3 s, game state "
               "kept). Covers control.lua and data.lua. Tick and new log errors in the answer.", schema({})),
    "ticks": ("Run about n game ticks as fast as possible (60 ticks = 1 s of game time), then hold. Answers the tick "
              "and any new errors in the log.", schema({"n": I}, ["n"])),
    "log": ("The game's log, last `lines` lines (60), or only lines with errors.",
            schema({"errors": B, "lines": I})),
    "output": ("A file from the game's script-output (helpers.write_file), or the list of them without a name.",
               schema({"name": S})),
    "stop": ("Stop the game.", schema({})),
    "save": ("Keep a restore point: the game as it is now, under `name` (letters, digits, _ . -). Points last until "
             "the next start.", schema({"name": S}, ["name"])),
    "restore": ("Go back to a restore point (~3 s): its game state with the mods copied again from their folders "
                "(like reload). Without a name, the list of points.", schema({"name": S})),
    "test": ("Check a mod before committing: lua_check.py over its folder, then its test/run.py (every case with "
             "--all, or one `case`), with `with` mods. Runs separate games (minutes for --all); the warm game is left "
             "alone. Answers PASS/FAIL, the Lua check, and only the failing cases with their log tail.",
             schema({"mod": {**S, "description": "absolute path of the mod folder (has test/run.py)"},
                     "case": S, "with": {"type": "array", "items": S}}, ["mod"])),
    "shot": ("The client window's picture (needs start with client). Shown at most `width` px wide (1280); "
             "click/hover/wheel take coordinates in the last shot's pixels. The full size is saved too.",
             schema({"width": I})),
    "click": ("Click in the client window at (x, y), in the last shot's pixels; `button` left (default), right or middle. "
              "The game runs until the server has applied it (about 1-2 s), then a new shot comes back unless `shot` "
              "is false. Input goes into the game itself (FSE), never the user's mouse.",
              schema({"x": I, "y": I, "button": {"type": "string", "enum": ["left", "right", "middle"]}, "shot": B},
                     ["x", "y"])),
    "hover": ("Move the client's mouse to (x, y) (tooltips), then like click.", schema({"x": I, "y": I, "shot": B},
                                                                                       ["x", "y"])),
    "wheel": ("Mouse wheel at (x, y): `notches` > 0 up, < 0 down; then like click.",
              schema({"x": I, "y": I, "notches": I, "shot": B}, ["x", "y", "notches"])),
    "key": ("Press a key in the client: a letter, digit, escape, enter, tab, space, backspace, delete, arrows, f1-f12; "
            "modifiers with + (\"control+c\", \"shift+e\"). Then like click.", schema({"key": S, "shot": B}, ["key"])),
    "type": ("Type text into the client's focused text field, then like click.", schema({"text": S, "shot": B},
                                                                                       ["text"])),
}


def call(name, args):
    if name == "start":
        return GAME.start(**args)
    if name == "lua":
        return GAME.lua(args["code"], args.get("mod"))
    if name == "ticks":
        return GAME.ticks(args["n"])
    if name == "log":
        return GAME.log(args.get("errors", False), args.get("lines", 60))
    if name == "output":
        return GAME.output(args.get("name"))
    if name in ("reload", "stop"):
        return getattr(GAME, name)()
    if name == "save":
        return GAME.save(args["name"])
    if name == "restore":
        return GAME.restore(args.get("name"))
    if name == "test":
        return test(**args)
    if name in ("shot", "click", "hover", "wheel", "key", "type"):
        return getattr(GAME, name)(**args)
    raise ValueError(f"no tool {name}")


def serve():
    for line in sys.stdin:
        msg = json.loads(line)
        if "id" not in msg:
            continue  # (notifications)
        method, params = msg.get("method"), msg.get("params") or {}
        reply = {"jsonrpc": "2.0", "id": msg["id"]}
        if method == "initialize":
            reply["result"] = {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                               "capabilities": {"tools": {}}, "serverInfo": {"name": "factorio", "version": "0.1.0"}}
        elif method == "tools/list":
            reply["result"] = {"tools": [{"name": n, "description": d, "inputSchema": s}
                                         for n, (d, s) in TOOLS.items()]}
        elif method == "tools/call":
            try:
                r, err = call(params["name"], params.get("arguments") or {}), False
                content = r if isinstance(r, list) else [{"type": "text", "text": str(r)}]  # (a list: text + image)
            except Exception as e:  # (an answer the agent can read beats a dead server)
                content, err = [{"type": "text", "text": f"{type(e).__name__}: {e}"}], True
            reply["result"] = {"content": content, "isError": err}
        elif method == "ping":
            reply["result"] = {}
        else:
            reply["error"] = {"code": -32601, "message": f"no method {method}"}
        print(json.dumps(reply), flush=True)


if __name__ == "__main__":
    serve()
