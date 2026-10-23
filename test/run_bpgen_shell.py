"""bpgen's web window (zzz-bpgen's web.lua + web/bpgen.html on fse-std's shells) in a real client, through dist's
launcher. Never global input: clicks and keys are posted to the game's and the page's own windows, pictures taken with
PrintWindow and composited as the screen shows them (the game, the page over it cut by its region).

Checks: the window opens as a web page (the Lua window hidden, its model); the page gets the state, its locale and
the game's icons; the preview is the only island and sits exactly in its hole; Plan pressed in the page plans (the
island shows the plan, the result's tiles in the page); a picker clicked opens the page's own picker (no game popup
under the page: the game has no GUI open), with the game's icons, searchable, and a pick in it reaches the hidden
window and plans again; a test
run started from the page streams its rate into the page's chart (x10); Copy, Place near me and Undo (the page's own
confirm) work; History opens its drawer with rows; a theme change reaches the page; the inventory over it hides it
and it comes back (a companion: not closed); the gear's "Game window" switches to the Lua window and the setting back
to the page (the plan kept); a saved page file reloads it; the page's X closes it (the page kept, hidden); opened again
from a button in another mod's window (that window the player's opened GUI, as Recipe Book's) it shows over it within
500 ms, as loaded (no drawer or menu left open), and still steps aside for a window opened after it.
Screenshots: bpgen/run/keep/web-*.png.

    python test/run_bpgen_shell.py [--keep]      (wrap it in gui_lock.py while other agents run GUI tests)
Gives up after 12 minutes in all (the game killed, exit 1): it never holds the GUI lock longer.
"""
import ctypes, json, os, re, shutil, subprocess, sys, threading, time, urllib.error, urllib.request
from ctypes import wintypes
from pathlib import Path

from PIL import Image

NATIVE = Path(__file__).resolve().parents[1]
BPGEN = NATIVE.parent / "bpgen"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from factorio_paths import run_dir, watch_game  # noqa: E402
from gui_input import click, focus, grab  # noqa: E402

# (a game with a window that isn't a test's: the user playing)
running = subprocess.run(["powershell", "-NoProfile", "-Command",
                          "Get-CimInstance Win32_Process -Filter \"name='factorio.exe'\" | ForEach-Object { $_.CommandLine }"],
                         capture_output=True, text=True).stdout.splitlines()
if any(l.strip() and not any(f in l for f in ("--benchmark", "--create", "--start-server", "--dump-data"))
       and "\\run\\" not in l.lower() and "/run/" not in l.lower() for l in running):
    raise SystemExit("Factorio is running with a window (your game?): close it first, this test opens one")

RUN = run_dir(Path(__file__).resolve().parent / "run")
CONFIG = RUN / "config-bpshell.ini"
CONFIG.write_text(re.split(r"(?m)^\[interface\]", (RUN / "config.ini").read_text(encoding="utf-8"))[0], encoding="utf-8")
MODS = RUN / "bpshell-mods"
OUT = RUN / "script-output"
KEEP = BPGEN / "run" / "keep"
TOKEN = "bpgen-shell-token"
KEY = "zzz-bpgen/bpgen"
u32 = ctypes.windll.user32
u32.SetProcessDPIAware()

shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
for m in ("fse-std", "fse-bridge"):
    shutil.copytree(NATIVE / "mods" / m, MODS / m)
shutil.copytree(BPGEN / "mod" / "zzz-bpgen", MODS / "zzz-bpgen")
shutil.copytree(NATIVE / "test" / "bpgen-shell-test", MODS / "bpgen-shell-test")
(MODS / "bpgen-shell-test" / "info.json").write_text(json.dumps({"name": "bpgen-shell-test", "version": "0.0.1",
    "title": "bpgen shell test", "author": "mtopfox", "factorio_version": "2.1", "dependencies": ["base", "zzz-bpgen"]}))
names = ["base", "elevated-rails", "quality", "space-age", "fse-std", "fse-bridge", "zzz-bpgen", "bpgen-shell-test"]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
OUT.mkdir(parents=True, exist_ok=True)
KEEP.mkdir(parents=True, exist_ok=True)
for f in KEEP.glob("web-*.png"):
    f.unlink()
env = dict(os.environ, FSE_WEB_TOKEN=TOKEN)
launch = [str(NATIVE / "dist" / "fse-launcher.exe"), "--config", str(CONFIG), "--mod-directory", str(MODS)]
save = RUN / "bpshell.zip"
save.unlink(missing_ok=True)
made = subprocess.run(launch + ["--create", str(save)], capture_output=True, text=True, errors="replace", env=env)
if not save.exists():
    raise SystemExit("--create failed: " + " | ".join(l for l in made.stdout.splitlines() if "Error" in l))
# (Copy and Place add to bpgen's history: the user's is put back afterwards)
sys.path.insert(0, str(BPGEN))
pypath = [d for line in (NATIVE / "dist" / "fse.env").read_text().splitlines() if line.startswith("FSE_PYPATH=")
          for d in line.split("=", 1)[1].split(";")]
hists = {BPGEN / "data" / "history.json"} | {Path(d) / "data" / "history.json" for d in pypath if Path(d).name.lower() == "bpgen"}
kept = {h: h.read_bytes() if h.exists() else None for h in hists}

results = []
GAME = None


def give_up():
    """the whole run took too long: the game killed, the user's history back, exit 1 (the GUI lock freed)"""
    print("FAIL  the test ran out of time (12 min): stopped", flush=True)
    if GAME:
        subprocess.run(["taskkill", "/PID", str(GAME.pid), "/T", "/F"], capture_output=True)
    for h, data in kept.items():
        if data is not None:
            h.write_bytes(data)
        else:
            h.unlink(missing_ok=True)
    os._exit(1)


_timer = threading.Timer(12 * 60, give_up)
_timer.daemon = True
_timer.start()


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""), flush=True)
    return ok


PORT = None


def api(path, body=None, timeout=20):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}", data=data, method="POST" if data else "GET",
                                 headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read() or b"{}")


def find_port():
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


def status():
    end = time.time() + 3
    while True:
        r = api("/api/native/web/shell_status", {})
        if r.get("result") or time.time() > end:
            return r.get("result") or {}
        time.sleep(0.1)


def shell():
    return status().get("shells", {}).get(KEY)


def call(fn, *args, iface="bpgen"):
    r = api("/api/game", {"interface": iface, "function": fn, "args": list(args)})
    if not r.get("ok"):
        print("  game call", iface, fn, "failed:", str(r.get("error"))[:300])
    return r.get("result")


def test_state():
    return call("state", iface="bpgen-shell-test") or {}


def web():
    return call("web_state", 1) or {}


def js(code):
    return api("/api/native/web/shell_eval", {"owner": "zzz-bpgen", "name": "bpgen", "js": code})


def seen():
    """what the page shows (its report, through the mod)"""
    js("bpgen.report()")
    time.sleep(0.25)
    return web().get("seen") or {}


def wait(cond, timeout=10.0, step=0.2):
    end = time.time() + timeout
    while True:
        try:
            v = cond()
        except Exception as e:  # (the game thread may be busy for a moment)
            v = None
        if v or time.time() > end:
            return v
        time.sleep(step)


def page_click(test_id, real=True):
    """a page control (data-test) clicked: a click posted to the page's browser window at its place, else the DOM's
    click(); -> how it was clicked"""
    js("bpgen.rects()")
    time.sleep(0.3)
    page = web().get("page") or {}
    r = (page.get("rects") or {}).get(test_id)
    s = shell()
    if real and r and s and s.get("browser_hwnd") and r[2] > 0:
        dpr = page.get("dpr") or 1
        x, y = s["screen"][0] + (r[0] + r[2] / 2) * dpr, s["screen"][1] + (r[1] + r[3] / 2) * dpr
        pt = wintypes.POINT(int(x), int(y))
        u32.ScreenToClient(s["browser_hwnd"], ctypes.byref(pt))
        at = int(pt.y) << 16 | int(pt.x) & 0xffff
        u32.PostMessageW(s["browser_hwnd"], 0x0200, 0, at)
        time.sleep(0.05)
        u32.PostMessageW(s["browser_hwnd"], 0x0201, 1, at)
        time.sleep(0.06)
        u32.PostMessageW(s["browser_hwnd"], 0x0202, 0, at)
        return "posted"
    js(f"document.querySelector('[data-test=\"{test_id}\"]').click()")
    return "dom"


def composite(path):
    s = shell()
    st = status()
    gh = st.get("game")
    g_path, s_path = OUT / "bpshell-game.png", OUT / "bpshell-window.png"
    if not gh or not grab(gh, g_path):
        return False
    g = Image.open(g_path).convert("RGB")
    if s and s.get("visible") and grab(s["hwnd"], s_path):
        w = Image.open(s_path).convert("RGB")
        mask = Image.new("L", w.size, 0)
        if s["region"]:
            for l, t, r, b in s["region"]:
                mask.paste(255, (l, t, r, b))
        else:
            mask.paste(255, (0, 0) + w.size)
        o = st["game_origin"]
        g.paste(w, (s["screen"][0] - o[0], s["screen"][1] - o[1]), mask)
    g.save(path)
    print("  screenshot", path, flush=True)
    return True


def holes_ok(ids):
    """each island's frame on its hole: its place and size (pixels) as the page's hole"""
    s, w = shell(), web()
    ds = (test_state().get("display_scale") or 1)
    out, ok = [], True
    for i in ids:
        h = (s.get("holes") or {}).get(i)
        f = (w.get("islands") or {}).get(i)
        if not (h and f and h.get("open")):
            ok = False
            out.append(f"{i}: hole {bool(h)} frame {bool(f)}")
            continue
        gx, gy, gw, gh = h["game"]
        dx, dy = f["x"] - gx, f["y"] - gy
        size = ""
        if i == "preview":
            v = w.get("view") or [0, 0]
            size = f" size d {v[0] - gw},{v[1] - gh}"
            ok = ok and abs(v[0] - gw) <= ds and abs(v[1] - gh) <= ds
        ok = ok and dx == 0 and dy == 0 and f["visible"]
        out.append(f"{i}: d {dx},{dy}{size}")
    return ok, "; ".join(out)


game = GAME = watch_game(launch + ["--load-game", str(save)], env=env)
try:
    if not check("web API up", wait(find_port, 180, 1.0), f"port {PORT}"):
        sys.exit(1)
    wait(lambda: test_state().get("ready"), 60, 0.5)
    call("open_window", 1, {"recipe": "iron-gear-wheel", "machine": "assembling-machine-2"})
    s = wait(lambda: (lambda x: x if x and x["ready"] and x["laid_out"] and x["visible"] else None)(shell()), 60, 0.3)
    if not check("the window opens as a web page (shell ready, laid out)", s, json.dumps(shell())[:300] if not s else s["url"]):
        sys.exit(1)
    w = web()
    ts = test_state()
    check("the Lua window is the hidden model", w.get("model") and ts.get("lua_window") and not ts.get("lua_visible"),
          f"model {w.get('model')}, lua window {ts.get('lua_window')}, visible {ts.get('lua_visible')}")
    sn = wait(lambda: (lambda x: x if x.get("dict", 0) > 100 and x.get("picks", 0) >= 3 and x.get("recipe") else None)(seen()), 20, 0.5)
    check("the page gets the state and the mod's locale", sn, sn and f"{sn['dict']} locale keys, {sn['picks']} pickers, recipe {sn['recipe']}, mode {sn['mode']}")
    isl = sorted((web().get("islands") or {}).keys())
    check("the preview is the only engine island", isl == ["preview"], isl)

    # Plan, pressed in the page
    how = page_click("plan")
    sn = wait(lambda: (lambda x: x if x.get("preview_on") and x.get("tiles", 0) > 0 else None)(seen()), 30, 1.0)
    if not sn and how == "posted" and not seen().get("status"):
        how = "posted, not taken: DOM click"
        page_click("plan", real=False)
    sn = sn or wait(lambda: (lambda x: x if x.get("preview_on") and x.get("tiles", 0) > 0 else None)(seen()), 150, 1.0)
    check("Plan in the page plans: the result's tiles in the page", sn, sn and f"{how}; tiles {sn['tiles_text']}, badges {sn['badges'][:3]}")
    time.sleep(1.5)  # (the drawer's slide, the island following it)
    w = web()
    cam = w.get("cam") or {}
    check("the preview island shows the plan (its camera on the preview surface)", cam.get("visible") and cam.get("surface", 1) != 1,
          f"cam {cam}")
    ok, detail = holes_ok(["preview"])
    check("the preview island sits exactly in its hole", ok, detail)
    sn = seen()
    check("the game's icons show in the page", sn.get("icons", 0) > 0, f"{sn.get('icons')} icons painted")
    composite(KEEP / "web-plan.png")
    if "--debug" in sys.argv:  # (the game left running here, to look at it by hand)
        os._exit(0)

    # a picker clicked (a click posted to the page): the page's own picker, over everything, no game popup
    how = page_click("pick_bpgen_recipe")
    sn = wait(lambda: (lambda x: x if (x.get("picker") or {}).get("rows", -1) > 0 else None)(seen()), 10, 0.4)
    if not sn and how == "posted":
        how = "posted, not taken: DOM click"
        page_click("pick_bpgen_recipe", real=False)
        sn = wait(lambda: (lambda x: x if (x.get("picker") or {}).get("rows", -1) > 0 else None)(seen()), 10, 0.4)
    time.sleep(1.2)  # (its icons)
    sn = seen()
    pk = sn.get("picker") or {}
    js("bpgen.rects()")
    time.sleep(0.3)
    r = ((web().get("page") or {}).get("rects") or {}).get("picker") or [0, 0, 0, 0]
    s = shell()
    inside = s and r[2] > 100 and r[3] > 100 and r[0] >= 0 and r[1] >= 0
    check("a picker opens the page's picker: visible (in the page, no game GUI under it), with the game's icons",
          pk.get("shown", 0) > 0 and pk.get("icons", 0) > 0 and inside and test_state().get("opened_type") == 0,
          f"{how}; {pk}, rect {r}, opened_gui_type {test_state().get('opened_type')}")
    composite(KEEP / "web-picker.png")
    js("const s = document.getElementById('pk-search'); s.value = 'copper cable'; s.dispatchEvent(new Event('input'))")
    time.sleep(0.5)
    js("document.querySelector('[data-test=\"pick:copper-cable\"]').click()")
    sn = wait(lambda: (lambda x: x if x.get("recipe") == "recipe/copper-cable" and x.get("preview_on") and not x.get("picker") else None)(seen()), 120, 1.0)
    check("a pick in the page's picker reaches the window (planned again)", sn, sn and f"recipe {sn['recipe']}, tiles {sn['tiles_text']}")
    time.sleep(2)

    # every picker of the line: opened in the page, searched, picked; the mod has it
    def pick_in_page(ref, name):
        js("document.querySelector('[data-test=\"pick_" + ref + "\"]').click()")
        if not wait(lambda: ((seen().get("picker") or {}).get("rows", -1)) > 0, 8, 0.4):
            return "no picker"
        js(f"const s = document.getElementById('pk-search'); s.value = '{name}'; s.dispatchEvent(new Event('input'))")
        time.sleep(0.4)
        js("document.querySelector('[data-test=\"pick:" + name + "\"]').click()")
        return wait(lambda: (seen().get("pks") or {}).get(ref, "").endswith("/" + name) and seen().get("pks")[ref], 8, 0.4)
    got = {ref: pick_in_page(ref, name) for ref, name in [("bpgen_machine", "assembling-machine-3"),
        ("bpgen_belt", "fast-transport-belt"), ("bpgen_module", "speed-module"), ("bpgen_beacon", "beacon"),
        ("bpgen_beacon_module", "speed-module")]}
    check("each picker: opened, searched, picked; the mod has the choice", all(v and v != "no picker" for v in got.values()), got)
    wait(lambda: not seen().get("picker"), 4, 0.3)

    # a test run from the page, x10: its rate reaches the page's chart
    page_click("tab_test", real=False)
    how = page_click("test")
    run = wait(lambda: seen().get("test_running"), 15, 0.5)
    if not run:
        page_click("test", real=False)
        run = wait(lambda: seen().get("test_running"), 15, 0.5)
    check("Test run starts from the page", run, how)
    page_click("speed", real=False)
    time.sleep(0.5)
    page_click("speed", real=False)
    sn = wait(lambda: (lambda x: x if x.get("chart_points", 0) >= 5 else None)(seen()), 150, 2.0)
    check("the test run's rate reaches the page's chart", sn,
          sn and f"{sn['chart_points']} points, rate {sn['test_rate']!r}, game speed {test_state().get('speed')}")
    time.sleep(1.0)
    composite(KEEP / "web-test.png")
    if seen().get("test_running"):
        page_click("test", real=False)  # (stopped)
        wait(lambda: not seen().get("test_running"), 10, 0.5)
    check("the game back at its own speed", wait(lambda: test_state().get("speed") == 1, 6, 0.5), f"speed {test_state().get('speed')}")

    # the dock's actions
    page_click("copy", real=False)
    sn = wait(lambda: (lambda x: x if any("opied" in t for t in x.get("toasts", [])) else None)(seen()), 6, 0.4)
    check("Copy: the page's toast says so", sn, sn and sn["toasts"])
    g0 = test_state().get("ghosts", 0)
    page_click("place", real=False)
    g1 = wait(lambda: (lambda n: n if n > g0 else None)(test_state().get("ghosts", 0)), 20, 0.5)
    check("Place near me puts ghosts down", g1, f"{g0} -> {g1}")
    page_click("undo", real=False)
    asked = wait(lambda: seen().get("modal"), 4, 0.3)
    time.sleep(0.4)
    composite(KEEP / "web-undo-confirm.png")
    page_click("confirm_yes", real=False)
    gone = wait(lambda: test_state().get("ghosts", 1) == g0, 10, 0.5)
    check("Undo asks in the page, then removes them", asked and gone, f"asked {bool(asked)}, ghosts {test_state().get('ghosts')}")

    # History: its drawer with the blueprints taken
    page_click("history", real=False)
    sn = wait(lambda: (lambda x: x if x.get("drawer") == "history" and x.get("history_rows", 0) > 0 else None)(seen()), 30, 0.5)
    check("History opens its drawer with rows", sn, sn and f"{sn['history_rows']} rows")
    time.sleep(1.0)
    composite(KEEP / "web-history.png")

    # the gear's menu, a theme change
    page_click("tab_result", real=False)
    call("set_theme", 1, "aquilo", iface="fse-std")
    time.sleep(1.5)
    composite(KEEP / "web-aquilo.png")
    page_click("gear", real=False)
    time.sleep(0.6)
    composite(KEEP / "web-menu.png")
    js("document.getElementById('menu').hidden = true; document.getElementById('win').classList.remove('pop-on')")
    call("set_theme", 1, "vanilla", iface="fse-std")

    # a companion: the inventory over it hides it, it comes back after (not closed)
    call("opened", "controller", iface="bpgen-shell-test")
    hid = wait(lambda: not shell()["visible"], 4, 0.2)
    still = web().get("open")
    call("opened", "none", iface="bpgen-shell-test")
    back = wait(lambda: shell() and shell()["visible"], 4, 0.2)
    check("another GUI hides it, it comes back (a companion stays open)", hid and still and back,
          f"hidden {bool(hid)}, open {still}, back {bool(back)}")
    time.sleep(0.5)
    ok, detail = holes_ok(["preview"])
    check("the preview island back in its hole", ok, detail)

    # the Lua window instead (the gear's "Game window"), then the web window again (the setting)
    page_click("gear", real=False)
    time.sleep(0.4)
    page_click("lua", real=False)
    lua = wait(lambda: (lambda t: t if t.get("lua_visible") and shell() is None else None)(test_state()), 10, 0.3)
    check("Game window: the Lua window opens, the page closes", lua, lua and f"setting {lua['setting']}")
    time.sleep(1.0)
    composite(KEEP / "web-lua-window.png")
    call("web_wanted", 1, True)
    s = wait(lambda: (lambda x: x if x and x["ready"] and x["visible"] else None)(shell()), 30, 0.3)
    sn = s and wait(lambda: (lambda x: x if x.get("preview_on") and x.get("tiles", 0) > 0 else None)(seen()), 20, 0.5)
    check("the web window again, the plan kept", s and sn and not test_state().get("lua_visible"),
          sn and f"tiles {sn['tiles_text']}")

    # a saved page file reloads the page; it gets the state again
    r0 = shell()["reloads"]
    page = MODS / "zzz-bpgen" / "web" / "bpgen.html"
    page.write_text(page.read_text(encoding="utf-8") + "\n<!-- edited -->\n", encoding="utf-8")
    ok = wait(lambda: shell()["reloads"] > r0 and shell()["ready"], 10, 0.3)
    sn = ok and wait(lambda: (lambda x: x if x.get("preview_on") else None)(seen()), 10, 0.5)
    check("live reload: a saved page reloads with its state", ok and sn)

    # the page's X closes the window; its page is kept, hidden, so it opens again at once (History's drawer and the
    # gear's menu left open: the page opened again shows neither)
    js("bpgen.openDrawer('history'); document.getElementById('menu').hidden = false")
    time.sleep(0.3)
    page_click("close", real=False)
    gone = wait(lambda: (lambda x: x and not x["visible"] and not test_state().get("lua_window"))(shell()), 8, 0.3)
    check("the page's X closes the window (its page kept, hidden)", gone)
    # opened again from a button in another mod's window (Recipe Book's: compat.lua's "recipe" action), that window
    # the player's opened GUI: the page shows over it, quickly, as loaded (no picker or drawer left open)
    call("opened", "custom", iface="bpgen-shell-test")
    time.sleep(0.5)
    t0 = time.time()
    call("click", 1, {"bpgen": "recipe", "recipe": "electronic-circuit"})
    shown = wait(lambda: (lambda x: x and x["visible"])(shell()), 5, 0.02)
    ms = (time.time() - t0) * 1000
    check("opened again from another mod's window: shown over it", shown, f"{ms:.0f} ms, opened {test_state().get('opened_type')}")
    check("... within 500 ms (the page kept loaded; it took about half a second, and stayed hidden over that window)",
          shown and ms < 500, f"{ms:.0f} ms")
    sn = wait(lambda: (lambda x: x if str(x.get("recipe")).endswith("electronic-circuit") else None)(seen()), 10, 0.3)
    check("... with the new recipe, nothing left open from before", sn and not sn.get("picker")
          and sn.get("drawer") != "history" and not sn.get("menu") and not sn.get("modal"),
          sn and f"recipe {sn.get('recipe')}, picker {sn.get('picker')}, drawer {sn.get('drawer')}, menu {sn.get('menu')}")
    call("opened", "none", iface="bpgen-shell-test")
    call("opened", "controller", iface="bpgen-shell-test")
    hid = wait(lambda: not shell()["visible"], 4, 0.2)
    call("opened", "none", iface="bpgen-shell-test")
    back = wait(lambda: shell()["visible"], 4, 0.2)
    check("... and still steps aside for a window opened after it", hid and back, f"hidden {bool(hid)}, back {bool(back)}")
    call("click", 1, {"bpgen": "close"})
    gone = wait(lambda: (lambda x: x and not x["visible"])(shell()), 8, 0.3)
    check("closed again", gone)
finally:
    if "--keep" not in sys.argv:
        subprocess.run(["taskkill", "/PID", str(game.pid), "/T", "/F"], capture_output=True)
    for h, data in kept.items():
        if data is not None:
            h.write_bytes(data)
        else:
            h.unlink(missing_ok=True)

passed = sum(ok for _, ok in results)
print(f"{passed}/{len(results)} passed; screenshots: {sorted(p.name for p in KEEP.glob('web-*.png'))}")
sys.stdout.flush()
os._exit(0 if passed == len(results) else 1)  # (the give-up timer's thread doesn't hold it)
