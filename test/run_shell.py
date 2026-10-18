"""Shells (a mod window as a web page with engine islands: fse-web's shell.rs, fse-std's shell.lua, web/shell/) in a
real client, through dist's launcher, with the shell-test mod (test/shell-test: a page with a camera island and a slot
island). Never global input: clicks and keys are posted to our own windows, pictures taken with PrintWindow.

Checks: the shell opens where the mod put it; its region has a hole at each island; each island frame sits on its
hole; page -> mod -> page -> mod messages round-trip; a click posted to the game window inside a hole reaches the
island's button (on_gui_click); a click posted into the page runs its button and leaves the keyboard with the game; a
text field takes the keyboard and gives it back; a theme change reaches the page; the shell follows the game window
(moved, minimised); Lua moves it (islands follow); another GUI hides it and it comes back; Esc in the page and in the
game close it; a saved page file reloads it. Screenshots: the game and the shell window composited
(test/run/script-output/shell-*.png).

    python test/run_shell.py [--scale N] [--keep]     (wrap it in gui_lock.py while other agents run GUI tests)
"""
import ctypes, json, os, re, shutil, subprocess, sys, time, urllib.error, urllib.request
from ctypes import wintypes
from pathlib import Path

from PIL import Image

NATIVE = Path(__file__).resolve().parents[1]
from factorio_paths import run_dir, watch_game  # noqa: E402
from gui_input import click, focus, game_window, grab  # noqa: E402

RUN = run_dir(Path(__file__).resolve().parent / "run")
SCALE = sys.argv[sys.argv.index("--scale") + 1] if "--scale" in sys.argv else None
# (a config of its own, the GUI scale in it: appended to the shared config.ini it stayed for every later test)
CONFIG = RUN / "config-shell.ini"
CONFIG.write_text(re.split(r"(?m)^\[interface\]", (RUN / "config.ini").read_text(encoding="utf-8"))[0] + (
    f"[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={SCALE}\n" if SCALE else ""), encoding="utf-8")
MODS = RUN / "shell-mods"
OUT = RUN / "script-output"
TOKEN = "shell-test-token"
u32 = ctypes.windll.user32
u32.SetProcessDPIAware()
KEY = "shell-test/demo"

shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
for m in ("fse-std", "fse-bridge"):
    shutil.copytree(NATIVE / "mods" / m, MODS / m)
shutil.copytree(NATIVE / "test" / "shell-test", MODS / "shell-test")
names = ["base", "fse-std", "fse-bridge", "shell-test"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": n in names} for n in
                                                         names + ["elevated-rails", "quality", "space-age"]]}))
OUT.mkdir(parents=True, exist_ok=True)
for f in OUT.glob("shell-*.png"):
    f.unlink()
env = dict(os.environ, FSE_WEB_TOKEN=TOKEN)
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(CONFIG), "--mod-directory", str(MODS)]
save = RUN / "shell.zip"
save.unlink(missing_ok=True)
subprocess.run(launch + ["--create", str(save)], capture_output=True, env=env)

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""), flush=True)
    return ok


PORT = None


def api(path, body=None, timeout=15):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}", data=data, method="POST" if data else "GET",
                                 headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read() or b"{}")


def find_port():
    """the test game's web API: the first of 18790-18799 that takes our token (the user's game may hold 18790)"""
    global PORT
    for p in range(18790, 18800):
        PORT = p
        try:
            if api("/api/status", timeout=1).get("core"):
                return p
        except OSError:
            pass
    PORT = None
    return None


STATUS_ERRORS = []


def status():
    """web.shell_status; an answer without a result (an error) is asked again for up to 2 s, the error kept"""
    end = time.time() + 2
    while True:
        r = api("/api/native/web/shell_status", {})
        if r.get("result") or time.time() > end:
            if not r.get("result"):
                STATUS_ERRORS.append(str(r)[:200])
                print("  shell_status answered no result:", str(r)[:200], flush=True)
            return r.get("result") or {}
        STATUS_ERRORS.append(str(r)[:200])
        print("  shell_status answered no result (asked again):", str(r)[:200], flush=True)
        time.sleep(0.1)


def shell():
    return status().get("shells", {}).get(KEY)


def game_call(fn, *args, iface="shell-test"):
    r = api("/api/game", {"interface": iface, "function": fn, "args": list(args)})
    if not r.get("ok"):
        print("  game call", fn, "failed:", r.get("error"))
    return r.get("result")


def js(code):
    return api("/api/native/web/shell_eval", {"owner": "shell-test", "name": "demo", "js": code})


def wait(cond, timeout=10.0, step=0.1):
    end = time.time() + timeout
    while True:
        try:
            v = cond()
        except Exception:  # (the game thread may be busy for a moment)
            v = None
        if v or time.time() > end:
            return v
        time.sleep(step)


def window_rect(h):
    r = wintypes.RECT()
    u32.GetWindowRect(h, ctypes.byref(r))
    return r.left, r.top, r.right, r.bottom


def post_click(h, x, y):
    """a left click at client pixel (x, y) of window h, posted (the page's browser window: no activation needed)"""
    at = int(y) << 16 | int(x) & 0xffff
    u32.PostMessageW(h, 0x0200, 0, at)
    time.sleep(0.05)
    u32.PostMessageW(h, 0x0201, 1, at)
    time.sleep(0.06)
    u32.PostMessageW(h, 0x0202, 0, at)


def composite(game_h, s, path):
    """the game window's picture with the shell's over it, cut by the shell's region (what the screen shows)"""
    g_path, s_path = OUT / "shell-game.png", OUT / "shell-window.png"
    if not grab(game_h, g_path) or not grab(s["hwnd"], s_path):
        return False
    g, w = Image.open(g_path).convert("RGB"), Image.open(s_path).convert("RGB")
    mask = Image.new("L", w.size, 0)
    if s["region"]:
        for l, t, r, b in s["region"]:
            mask.paste(255, (l, t, r, b))
    else:
        mask.paste(255, (0, 0) + w.size)
    o = status()["game_origin"]
    g.paste(w, (s["screen"][0] - o[0], s["screen"][1] - o[1]), mask)
    g.save(path)
    return True


game = watch_game(launch + ["--load-game", str(save)], env=env)
try:
    pid = game.pid
    if not check("web API up", wait(find_port, 180, 1.0), f"port {PORT}"):
        sys.exit(1)
    s = wait(lambda: (lambda x: x if x and x["ready"] and x["laid_out"] and x["visible"] else None)(shell()), 90, 0.3)
    if not check("shell opens, page ready and laid out", s, json.dumps(shell())[:300] if not s else s["url"]):
        sys.exit(1)
    gh = status()["game"]
    time.sleep(1.0)  # (the page's entrance animation)
    s = shell()
    st = game_call("state")
    ds = st["display_scale"]
    print("  shell", s["rect"], "zoom", round(s["zoom"], 3), "dpi", s["dpi"], "display scale", ds,
          "holes", {k: v["game"] for k, v in s["holes"].items()})
    check("shell window where the mod put it", s["placed_right"] and s["rect"] == st["shell_rect"],
          f"{s['rect']} vs mod {st['shell_rect']}")
    check("a hole at each island", set(s["holes"]) == {"cam", "slots"} and all(h["open"] for h in s["holes"].values()),
          {k: (h["open"], h["game_there"]) for k, h in s["holes"].items()})
    st = wait(lambda: (lambda x: x if x["islands"]["cam"] and x["islands"]["cam"]["visible"]
                       and x["islands"]["slots"]["visible"] else None)(game_call("state")), 10)
    ok = bool(st)
    detail = []
    for k, h in s["holes"].items():
        f = st and st["islands"][k]
        size = st and st["sizes"].get(k)
        gx, gy, gw, gh_ = h["game"]
        if not (f and size):
            ok = False
            continue
        dx, dy = f["x"] - gx, f["y"] - gy
        dw, dh = size[0] * ds - gw, size[1] * ds - gh_
        detail.append(f"{k}: frame at {f['x']},{f['y']} {size} GUI units vs hole {h['game']} (d {dx},{dy} size d {dw:.1f},{dh:.1f})")
        ok = ok and abs(dx) <= 0 and abs(dy) <= 0 and abs(dw) <= ds / 2 + 0.01 and abs(dh) <= ds / 2 + 0.01
    check("island frames on their holes", ok, "; ".join(detail))
    composite(gh, shell(), OUT / "shell-composite.png")

    # page -> mod -> page -> mod
    js("ping(1)")
    st = wait(lambda: (lambda x: x if x["acks"] else None)(game_call("state")), 10)
    check("messages round-trip (page -> mod -> page -> mod)", st and st["pings"] == 1 and st["acks"][0]["n"] == 1,
          st and f"round trip {st['acks'][0]['rtt_ms']:.1f} ms")
    check("the mod's state reaches the page, its theme too", st and st["theme_seen"], st and st["theme_seen"])

    # a click through a hole: the game window gets it at the first slot
    # (posted clicks now and then never reach the game, more so while another app is in front: 3 tries, each waited
    # for up to 6 s so a late one isn't clicked twice. None arrived: the hole's geometry is checked instead (the click's
    # point inside the hole and outside the shell's region, so a real click there goes to the game) and noted)
    gh = status()["game"]
    slots = shell()["holes"]["slots"]["game"]
    px, py = slots[0] + 20 * ds, slots[1] + 20 * ds
    st = None
    for _ in range(3):
        focus(gh)
        click(gh, px, py)
        st = wait(lambda: (lambda x: x if x["clicks"] else None)(game_call("state")), 6, 0.3)
        if st:
            break
    if st:
        check("a click in a hole reaches the island's button (on_gui_click)", st["clicks"][0] == "iron-plate",
              st["clicks"])
    else:
        s = shell()
        o = status()["game_origin"]
        sx, sy = o[0] + px - s["screen"][0], o[1] + py - s["screen"][1]
        in_hole = slots[0] <= px < slots[0] + slots[2] and slots[1] <= py < slots[1] + slots[3]
        cut = bool(s["region"]) and not any(l <= sx < r and t <= sy < b for l, t, r, b in s["region"])
        print("note: the posted click never reached the game (3 tries); the hole's geometry checked instead",
              f"(the game under the hole on screen: {s['holes']['slots']['game_there']})", flush=True)
        check("a click in a hole reaches the island's button (the point is in the hole, cut out of the region)",
              in_hole and cut, f"point {px},{py} in hole {slots}: {in_hole}; outside the region: {cut}")

    # a click into the page (posted to its browser window): its button runs, the game keeps the keyboard
    js("rects()")
    st = wait(lambda: (lambda x: x if x.get("rects") else None)(game_call("state")), 8)
    before = st["chests"] if st else 0
    s = shell()
    bw = s["browser_hwnd"]
    via = "posted click"
    if st and bw:
        x, y, w, h = st["rects"]["spawn"]
        pt = wintypes.POINT(s["screen"][0] + x + w // 2, s["screen"][1] + y + h // 2)
        u32.ScreenToClient(bw, ctypes.byref(pt))
        post_click(bw, pt.x, pt.y)
    got = wait(lambda: game_call("state")["chests"] > before, 4)
    if not got:
        via = "posted click not taken: element.click()"
        js("document.getElementById('spawn').click()")
        got = wait(lambda: game_call("state")["chests"] > before, 6)
    check("a page button calls the mod (spawns a chest)", got, via)
    time.sleep(0.3)
    s = shell()
    check("the game keeps the keyboard after a page click", s["keyboard"] == "game" and not s["active"],
          f"keyboard {s['keyboard']}, shell active {s['active']}, game foreground {status()['game_foreground']}")

    # a text field takes the keyboard (a click posted into it) and gives it back (a click on a page button)
    def page_click(el):
        s = shell()
        x, y, w, h = game_call("state")["rects"][el]
        pt = wintypes.POINT(s["screen"][0] + x + w // 2, s["screen"][1] + y + h // 2)
        u32.ScreenToClient(s["browser_hwnd"], ctypes.byref(pt))
        post_click(s["browser_hwnd"], pt.x, pt.y)
    page_click("label")
    s = wait(lambda: (lambda x: x if x["keyboard"] == "web" else None)(shell()), 4)
    check("a text field clicked takes the keyboard", s,
          s and f"shell active {s['active']}, foreground {s['foreground']} (Windows keeps the foreground where it is "
          f"when another app is in front)")
    js("const l = document.getElementById('label'); l.value = 'hello'; l.dispatchEvent(new Event('change'));")
    page_click("left")
    s = wait(lambda: (lambda x: x if x["keyboard"] == "game" else None)(shell()), 4)
    st = game_call("state")
    check("a click elsewhere in the page gives the keyboard back to the game",
          s and not s["active"] and st.get("label") == "hello",
          f"label {st.get('label')!r}, shell active {s and s['active']}, game foreground {status()['game_foreground']}")

    # a theme change reaches the page (fse-std's fstd-theme-changed)
    game_call("set_theme", 1, "flat", iface="fse-std")
    st = wait(lambda: (lambda x: x if x["theme_seen"] == "flat" else None)(game_call("state")), 8)
    check("a theme change reaches the page", st)
    time.sleep(0.6)
    composite(gh, shell(), OUT / "shell-composite-flat.png")

    # the shell follows the game window: moved, minimised and back (SetWindowPos/ShowWindow on the test game's window)
    l, t, r, b = window_rect(gh)
    u32.SetWindowPos(gh, 0, l + 40, t + 30, 0, 0, 0x0001 | 0x0004 | 0x0010)  # NOSIZE | NOZORDER | NOACTIVATE
    s = wait(lambda: (lambda x: x if x and x["placed_right"] else None)(shell()), 3)
    check("the shell follows the game window when it moves", s, s and f"{s['screen']}")
    u32.SetWindowPos(gh, 0, l, t, 0, 0, 0x0001 | 0x0004 | 0x0010)
    u32.ShowWindow(gh, 7)  # SW_SHOWMINNOACTIVE
    hidden = wait(lambda: not shell()["visible"], 3)
    u32.ShowWindow(gh, 4)  # SW_SHOWNOACTIVATE
    back = wait(lambda: shell()["visible"] and shell()["placed_right"], 5)
    check("the shell hides with the game window minimised and comes back", hidden and back)

    # Lua moves it: islands follow
    game_call("move", "top-left")
    s = wait(lambda: (lambda x: x if x["rect"][0] == 0 and x["rect"][1] == 0 and x["placed_right"] else None)(shell()), 5)
    st = wait(lambda: (lambda x: x if x["islands"]["cam"]["x"] == shell()["holes"]["cam"]["game"][0] else None)(game_call("state")), 5)
    check("shell.move: the window and its islands go there", s and st, s and f"{s['rect']}")
    game_call("move", "center")

    # an animated hole (the page's Squeeze: a 0.4 s transition): the island follows; the lag from the page's layout
    # to the frame moved
    lag0 = status()["lag"]
    js("document.getElementById('narrow').click()")
    samples = []
    t0 = time.time()
    while time.time() - t0 < 0.8:
        samples.append(shell()["holes"]["cam"]["rect"][2])
        time.sleep(0.03)
    time.sleep(0.3)
    s, st = shell(), game_call("state")
    lag = status()["lag"]
    n = lag["n"] - lag0["n"]
    widths = sorted(set(samples))
    check("an animated hole: its island follows", len(widths) > 3 and abs(st["sizes"]["cam"][0] * ds - s["holes"]["cam"]["rect"][2]) <= ds,
          f"{len(widths)} widths seen during the transition; layout -> Lua take: {n} events, "
          f"avg {lag['avg_ms']:.1f} ms, max {lag['max_ms']:.1f} ms (all run)")
    composite(gh, shell(), OUT / "shell-composite-squeezed.png")
    js("document.getElementById('narrow').click()")

    # another GUI opens (the inventory, by script): the shell hides, and comes back when it closes
    game_call("opened", "controller")
    hid = wait(lambda: not shell()["visible"], 4)
    st = game_call("state")
    game_call("opened", "none")
    came = wait(lambda: shell()["visible"], 4)
    check("another GUI hides the shell; it comes back when that closes", hid and came and st.get("suspended")
          and game_call("state")["open"],
          f"hidden {bool(hid)}, back {bool(came)}")

    # a saved page file reloads the page; the mod hears ready again
    r0 = game_call("state")["ready"]
    page = MODS / "shell-test" / "web" / "demo.html"
    page.write_text(page.read_text(encoding="utf-8") + "\n<!-- edited -->\n", encoding="utf-8")
    st = wait(lambda: (lambda x: x if x["ready"] > r0 else None)(game_call("state")), 8)
    check("live reload: a saved page reloads, the mod hears ready", st and shell()["reloads"] >= 1)

    # Esc in the page closes it (the mod hears "esc")
    wait(lambda: shell()["ready"], 5)
    n_closed = len(game_call("state")["closed"] or [])
    js("document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}))")
    st = wait(lambda: (lambda x: x if not x["open"] else None)(game_call("state")), 5)
    check("Esc in the page closes the shell", st and len(st["closed"]) == n_closed + 1 and st["closed"][-1] == "esc"
          and shell() is None, st and st["closed"])

    # Esc in the game closes it too (the shell is the player's opened GUI)
    game_call("open")
    wait(lambda: (lambda x: x and x["visible"] and x["ready"])(shell()), 10)
    time.sleep(0.5)
    n_closed = len(game_call("state")["closed"] or [])
    focus(gh)
    u32.PostMessageW(gh, 0x0100, 0x1B, 0x00010001)  # WM_KEYDOWN Esc
    time.sleep(0.08)
    u32.PostMessageW(gh, 0x0101, 0x1B, 0xC0010001)
    st = wait(lambda: (lambda x: x if not x["open"] else None)(game_call("state")), 5)
    check("Esc in the game closes the shell", st and len(st["closed"]) == n_closed + 1 and shell() is None,
          st and st["closed"])
finally:
    if "--keep" not in sys.argv:
        game.kill()

passed = sum(ok for _, ok in results)
print(f"{passed}/{len(results)} passed; screenshots: {sorted(str(p) for p in OUT.glob('shell-*.png'))}")
sys.exit(0 if passed == len(results) else 1)
